import Foundation

@usableFromInline
struct Groups {
    @usableFromInline
    final class Storage {
        @usableFromInline
        var groups: [GroupSignature: any GroupProtocol]
        /// Registry of which component is already owned by which group (to avoid conflicting orderings).
        var ownedTags = ComponentSignature()

        func copy() -> Storage {
            Storage(groups: groups)
        }

        init(groups: [GroupSignature: any GroupProtocol] = [:]) {
            self.groups = groups
        }
    }

    @usableFromInline
    private(set) var storage = Storage()

    @usableFromInline
    mutating func add(_ group: some GroupProtocol, in coordinator: Coordinator) {
        if !isKnownUniquelyReferenced(&storage) {
            storage = storage.copy()
        }
        try! group.acquire(in: &storage.ownedTags)
        storage.groups[group.signature] = group
        group.rebuild(in: coordinator)
    }

    @usableFromInline
    func groupSize(_ signature: GroupSignature) -> Int? {
        storage.groups[signature]?.size
    }

    @usableFromInline
    func groupSlots(_ signature: GroupSignature, in pool: inout ComponentPool) -> ArraySlice<SlotIndex>? {
        guard let group = storage.groups[signature] else {
            return nil
        }
        return group.slotsSlice(in: &pool)
    }

    @usableFromInline
    func groupSlotsWithOwned(_ signature: GroupSignature, in pool: inout ComponentPool) -> (ArraySlice<SlotIndex>, ComponentSignature)? {
        guard let group = storage.groups[signature] else {
            return nil
        }
        return (group.slotsSlice(in: &pool), group.owned)
    }

    @usableFromInline
    mutating func remove(_ signature: QuerySignature) {
        if !isKnownUniquelyReferenced(&storage) {
            storage = storage.copy()
        }

        let groupSignature = GroupSignature(signature)
        guard let group = storage.groups.removeValue(forKey: groupSignature) else {
            return
        }
        group.release(from: &storage.ownedTags)
    }

    @usableFromInline
    func onComponentAdded(_ tag: ComponentTag, entity: Entity.ID, in coordinator: Coordinator) {
        for group in storage.groups.values {
            group.onComponentAdded(tag, entity: entity, in: coordinator)
        }
    }

    @usableFromInline
    func onWillRemoveComponent(_ tag: ComponentTag, entity: Entity.ID, in coordinator: Coordinator) {
        for group in storage.groups.values {
            group.onWillRemoveComponent(tag, entity: entity, in: coordinator)
        }
    }
}

extension Groups {
    /// Returns the primary tag and current size for a group signature if present.
    @inlinable @inline(__always)
    func primaryAndSize(_ signature: GroupSignature) -> (primary: ComponentTag, size: Int)? {
        guard let group = storage.groups[signature] else { return nil }
        return (group.primary, group.size)
    }
}

extension Groups {
    /// Returns whether the group is owning (reorders component storage) for the given signature.
    @inlinable @inline(__always)
    func isOwning(_ signature: GroupSignature) -> Bool {
        guard let group = storage.groups[signature] else { return false }
        return group.isOwning
    }
}

// MARK: - SparseSet helpers for grouping (swap & index helpers)

extension SparseSet {
    /// Returns the dense index for the given slot if present.
    @inlinable @inline(__always)
    internal func denseIndex(for slot: SlotIndex) -> Int? {
        assert(slots.indices.contains(slot))
//        if slots.contains(index: slot) {
            return slots[slot]
//        }
//        return nil
    }
}

// MARK: - AnyComponentArray helper to access underlying typed SparseSet

extension AnyComponentArray {
    /// Execute a closure with a mutable reference to the underlying typed SparseSet for `C`.
    /// This allows partitioning & swapping for grouping.
    @inlinable @inline(__always)
    mutating func _withMutableSparseSet<C: Component, R>(
        _ type: C.Type,
        _ body: (inout ComponentArray<C>) throws -> R
    ) rethrows -> R {
        // This mirrors how withStorage is implemented internally.
        let box = Unmanaged.passUnretained(base as! ComponentArrayBox<C>)
        return try body(&box.takeUnretainedValue().base)
    }

    /// Execute a closure with a read-only view of the "dense index -> SlotIndex" mapping.
    /// Useful to determine which entity slot is stored at a given dense position.
//    @inlinable @inline(__always)
//    func _withComponentsToSlots<C: Component, R>(
//        _ type: C.Type,
//        _ body: (ContiguousArray<SlotIndex>) throws -> R
//    ) rethrows -> R {
//        let typed = base as! ComponentArrayBox<C>
//        return try body(typed.componentsToEntites)
//    }
}

//struct Both<each Queried> {
//    struct With<each Included> {
//        struct Excluded<each Excluded> {
//            let queried: (repeat each Queried)
//            let with: (repeat each Included)
//            let excluded: (repeat each Excluded)
//        }
//    }
//}
//func make<each A, each B, each C>(
//    a: repeat each A,
//    b: repeat each B,
//    c: repeat each C
//) -> Both<repeat each A>.With<repeat each B>.Excluded<repeat each C>{
//    Both.With.Excluded(queried: (repeat each a), with: (repeat each b), excluded: (repeat each c))
//}
//func wow() {
//    let m = make(a: 4, "", b: 4.5)
//}

/** TODO:
 ComponentPool need to own a list of all groups.
 ComponentPool needs to forward add/remove events to every group, so that they can sort if needed.
 I think I wouldn't need any more changes, the regular query iteration would just naturally gain an performance boost.

 There are two iteration styles:
 1. Iterate over base list and check for a valid entity on each iteration (getArrays/baseAndOther, or getBaseSparseList/base for the signature check approach)
 2. Precompute and cache all valid entities beforehand and iterate that list (slots)

 Compared to EnTT we would have:
 - Fully owned group:
 coordinator.group<Position, Velocity>()
 Query { … }.performPreloaded { … } // `performPreloaded` just means that we will create and cache the list of entities beforehand and won't have checks inside the loop.
 - View
 Query { … }.perform { … } // This would still benefit from a groups sorting when using the same components.

 How can I name these things better, considering I also have performParallel and fetchOne, fetchAll.

 I might can pull off the Bevy iterator interface:
 func system(query1: Query<Write<Position>, Without<Velocity>>, query2: GroupQuery<Material, Position>) {
    let fetchAll = Array(query1)
    for (material, position) in query2 {
        …
    }
 }
 */

// EnTT overview:
// - View: Take sparse set order as it is, filter during iteration
// - Group: Create and maintain an entity list for this signature. (Sorted by custom predicate.)
//          (For owning components: Also sort the dense array)

// TODO: EnTT groups can just use Array.partition(by:)?

// MARK: - Group

@usableFromInline
protocol GroupProtocol {
    func rebuild(in coordinator: Coordinator)
    func onComponentAdded(_ tag: ComponentTag, entity: Entity.ID, in coordinator: Coordinator)
    func onWillRemoveComponent(_ tag: ComponentTag, entity: Entity.ID, in coordinator: Coordinator)

    func acquire(in signature: inout ComponentSignature) throws(GroupAcquireError)
    func release(from signature: inout ComponentSignature)

    var signature: GroupSignature { get }
    var owned: ComponentSignature { get }

    var size: Int { get }
    var primary: ComponentTag { get }

    func slotsSlice(in pool: inout ComponentPool) -> ArraySlice<SlotIndex>

    var isOwning: Bool { get }
}

struct GroupAcquireError: Error {}

/// A high-performance "owned group" that packs all entities matching the required signature
/// into a contiguous prefix of the primary component's dense storage.
public final class Group<each Owned: Component>: GroupProtocol {
    // All owned tags, including Primary and the rest of the pack
    /// The primary owned component. Can change during rebuilds.
    public private(set) var primary: ComponentTag
    private let ownedComponents: Set<ComponentTag>
    public let owned: ComponentSignature
    public let signature: GroupSignature

    /// Contains owned, backstage and excluded components.
    /// - Attention: Only use this to quickly filter if component changes are relevant to this group. Don't use this for membership tests.
    ///              "Own A, B, Exclude X, Y" and "Own X, Y, Exclude A, B" must both be supported for membership tests.
    public let fullSignature: ComponentSignature

    // Membership filter (derived from a Query or passed explicitly)
    @usableFromInline let backstageSignature: ComponentSignature
    @usableFromInline let excludeSignature: ComponentSignature
    private let backstageComponents: Set<ComponentTag>
    private let excludedComponents: Set<ComponentTag>
    private let query: Query<repeat each Owned>

    /// Number of packed entities at the front of the primary component's storage.
    public private(set) var size: Int = 0

    public init(query: Query<repeat each Owned>) {
        var result: Set<ComponentTag> = []
        var first = true
        var prim: ComponentTag?
        for owned in repeat (each Owned).self {
            precondition(owned.QueriedComponent.self != Never.self, "Group members must be stored components.")
            if owned is any OptionalQueriedComponent.Type {
                preconditionFailure("A group cannot own an optional component.")
            }
            result.insert(owned.QueriedComponent.componentTag)
            if first {
                first = false
                prim = owned.QueriedComponent.componentTag
            }
        }
        self.query = query
        precondition(prim != nil, "Group must have at least one owning component.")
        primary = prim.unsafelyUnwrapped
        ownedComponents = result
        owned = ComponentSignature(ownedComponents)
        backstageSignature = query.backstageSignature
        excludeSignature = query.excludedSignature
        backstageComponents = query.backstageComponents
        excludedComponents = query.excludedComponents
        fullSignature = query.signature.union(query.excludedSignature)
        signature = GroupSignature(query.querySignature)
    }
    
    public convenience init(@QueryBuilder query: () -> BuiltQuery<repeat each Owned>) {
        self.init(query: query().composite)
    }

    @usableFromInline
    func acquire(in signature: inout ComponentSignature) throws(GroupAcquireError) {
        guard signature.isDisjoint(with: owned) else {
            throw GroupAcquireError()
        }
        signature.formUnion(owned)
    }

    @usableFromInline
    func release(from signature: inout ComponentSignature) {
        signature.remove(owned)
    }

    /// Build (or rebuild) the contiguous partition for this group.
    /// This partitions the primary component's dense storage so that all matching entities are in [0 ..< size).
    public func rebuild(in coordinator: Coordinator) {
        // Dynamically select the primary as the smallest owned storage to minimize scan/swaps
        var selectedPrimary: ComponentTag? = nil
        var minCount: Int = .max
        for tag in ownedComponents {
            if let arr = coordinator.pool.components[tag] {
                let c = arr.componentsToEntites.count
                if c < minCount {
                    minCount = c
                    selectedPrimary = tag
                }
            }
        }
        if let sp = selectedPrimary, sp != self.primary {
            self.primary = sp
        }

        let requiredSignature = query.signature
        let excludeSignature = self.excludeSignature
        guard !requiredSignature.isEmpty else {
            size = 0
            return
        }
        @inline(__always)
        func passes(_ slot: SlotIndex) -> Bool {
            let signature = coordinator.entitySignatures[slot.index]
            return requiredSignature.isSubset(of: signature)
                && excludeSignature.isDisjoint(with: signature)
        }

        // Access primary storage
        guard var primaryArray = coordinator.pool.components[primary] else {
            size = 0
            return
        }

        // Find the concrete primary owned type and run the partition on it
        var handledPrimary = false
        for ownedComponentType in repeat (each Owned).QueriedComponent.self {
            if ownedComponentType.componentTag != self.primary { continue }
            handledPrimary = true

            // 1) Partition primary in a single pass (no swap log needed)
            primaryArray._withMutableSparseSet(ownedComponentType) { primarySet in
                let total = primarySet.count
                var write = 0

                // Single-pass partition
                var read = 0
                while read < total {
                    let slot = primarySet.keys[read]
                    if passes(slot) {
                        if read != write {
                            primarySet.swapDenseAt(read, write)
                        }
                        write &+= 1
                    }
                    read &+= 1
                }
                self.size = write
            }

            // 2) Mirror the primary permutation to all other owned storages with a single-pass placement
            if self.size > 0 {
                // Capture the packed primary order for indices 0..<size
                let primaryPacked = primaryArray.componentsToEntites[..<self.size]

                for otherOwnedType in repeat (each Owned).QueriedComponent.self {
                    let tag = otherOwnedType.componentTag
                    if tag == self.primary { continue }
                    guard var otherArray = coordinator.pool.components[tag] else { continue }

                    otherArray._withMutableSparseSet(otherOwnedType) { otherSet in
                        // For each desired position j, ensure the desired slot is at j if present
                        var j = 0
                        while j < self.size {
                            let desiredSlot = primaryPacked[j]
                            if let currentIndex = otherSet.denseIndex(for: desiredSlot), currentIndex != j {
                                otherSet.swapDenseAt(currentIndex, j)
                            }
                            j &+= 1
                        }
                    }
                }
            }

            break // We handled the primary
        }

        if !handledPrimary { return }
    }

    /// Incremental hook to be called when a component is **added** to an entity.
    /// If the entity now matches the group, it is swapped into the packed prefix.
    public func onComponentAdded(_ tag: ComponentTag, entity: Entity.ID, in coordinator: Coordinator) {
        // Only proceed if the added tag touches this group's signature and primary exists
        guard fullSignature.contains(tag), var primaryArray = coordinator.pool.components[primary] else { return }

        let requiredSignature = query.signature
        let excludeSignature = self.excludeSignature
        guard !requiredSignature.isEmpty else {
            size = 0
            return
        }
        @inline(__always)
        func passes(_ slot: SlotIndex) -> Bool {
            let signature = coordinator.entitySignatures[slot.index]
            return requiredSignature.isSubset(of: signature)
            && excludeSignature.isDisjoint(with: signature)
        }

        // Defer mirroring swap to other owned storages until after we release primarySet
        var pending: (slot: SlotIndex, targetIndex: Int)? = nil

        for ownedComponentType in repeat (each Owned).QueriedComponent.self {
            if ownedComponentType.componentTag != self.primary { continue }
            primaryArray._withMutableSparseSet(ownedComponentType) { primarySet in
                guard let idx = primarySet.denseIndex(for: entity.slot) else { return }

                if excludedComponents.contains(tag) {
                    // If tag is excluded and entity is in packed prefix, swap it out
                    if idx < size {
                        let last = size &- 1
                        let aSlot = primarySet.keys[idx]
                        primarySet.swapDenseAt(idx, last)
                        size = last
                        pending = (slot: aSlot, targetIndex: last)
                    }
                } else {
                    // If entity matches after addition and is not in packed prefix, swap it in
                    if idx >= size, passes(entity.slot) {
                        let insertIndex = size
                        let aSlot = entity.slot
                        primarySet.swapDenseAt(idx, insertIndex)
                        size &+= 1
                        pending = (slot: aSlot, targetIndex: insertIndex)
                    }
                }
            }
            break
        }

        // Mirror the swap to all other owned storages outside the primary closure
        if let p = pending {
            for otherOwnedType in repeat (each Owned).QueriedComponent.self {
                let tag = otherOwnedType.componentTag
                if tag == self.primary { continue }
                guard var otherArray = coordinator.pool.components[tag] else { continue }
                otherArray._withMutableSparseSet(otherOwnedType) { otherSet in
                    if let ci = otherSet.denseIndex(for: p.slot), ci != p.targetIndex {
                        otherSet.swapDenseAt(ci, p.targetIndex)
                    }
                }
            }
        }
    }

    /// Incremental hook to be called when a component is **removed** from an entity.
    /// If the entity was part of the group, it is swapped out of the packed prefix.
    public func onWillRemoveComponent(_ tag: ComponentTag, entity: Entity.ID, in coordinator: Coordinator) {
        guard self.fullSignature.contains(tag) else { return }
        guard var primaryArray = coordinator.pool.components[primary] else { return }

        let requiredSignature = query.signature
        let excludeSignature = self.excludeSignature
        guard !requiredSignature.isEmpty else {
            size = 0
            return
        }
        @inline(__always)
        func passes(_ slot: SlotIndex) -> Bool {
            let signature = coordinator.entitySignatures[slot.index]
            return requiredSignature.isSubset(of: signature)
            && excludeSignature.isDisjoint(with: signature)
        }

        var pending: (slot: SlotIndex, targetIndex: Int)? = nil

        for ownedComponentType in repeat (each Owned).QueriedComponent.self {
            if ownedComponentType.componentTag != self.primary { continue }
            primaryArray._withMutableSparseSet(ownedComponentType) { primarySet in
                guard let idx = primarySet.denseIndex(for: entity.slot) else { return }

                if excludedComponents.contains(tag) {
                    // If excluded tag removed and entity is outside packed prefix, include if now valid
                    if idx >= size, passes(entity.slot) {
                        let insertIndex = size
                        let aSlot = entity.slot
                        primarySet.swapDenseAt(idx, insertIndex)
                        size &+= 1
                        pending = (slot: aSlot, targetIndex: insertIndex)
                    }
                } else if ownedComponents.contains(tag) || backstageComponents.contains(tag) {
                    // If owned/backstage removed and entity is inside packed prefix, swap it out
                    if idx < size {
                        let last = size &- 1
                        let aSlot = primarySet.keys[idx]
                        primarySet.swapDenseAt(idx, last)
                        size = last
                        pending = (slot: aSlot, targetIndex: last)
                    }
                }
            }
            break
        }

        if let p = pending {
            for otherOwnedType in repeat (each Owned).QueriedComponent.self {
                let tag = otherOwnedType.componentTag
                if tag == self.primary { continue }
                guard var otherArray = coordinator.pool.components[tag] else { continue }
                otherArray._withMutableSparseSet(otherOwnedType) { otherSet in
                    if let ci = otherSet.denseIndex(for: p.slot), ci != p.targetIndex {
                        otherSet.swapDenseAt(ci, p.targetIndex)
                    }
                }
            }
        }
    }

    /// Typed convenience.
    @inlinable @inline(__always)
    public func onComponentAdded<C: Component>(_ type: C.Type, entity: Entity.ID, in coordinator: Coordinator) {
        onComponentAdded(C.componentTag, entity: entity, in: coordinator)
    }

    /// Typed convenience.
    @inlinable @inline(__always)
    public func onWillRemoveComponent<C: Component>(_ type: C.Type, entity: Entity.ID, in coordinator: Coordinator) {
        onWillRemoveComponent(C.componentTag, entity: entity, in: coordinator)
    }
    
    public var isOwning: Bool { true }
    
    public func slotsSlice(in pool: inout ComponentPool) -> ArraySlice<SlotIndex> {
        return pool.components[primary]?.componentsToEntites[..<size] ?? []
    }
}

/// A non-owning group that maintains an internal packed list of matching entity slots.
public final class NonOwningGroup: GroupProtocol {
    public let signature: GroupSignature
    public var size: Int { slots.count }
    public var primary: ComponentTag { ComponentTag(rawValue: -1) } // sentinel, unused
    public var isOwning: Bool { false }
    public let owned = ComponentSignature()

    // Required/backstage/excluded component sets
    private let requiredComponents: Set<ComponentTag>
    private let excludedComponents: Set<ComponentTag>

    // Internal packed list and sparse index for O(1) membership
    private var slots: ContiguousArray<SlotIndex> = []
    private var sparseIndex: ContiguousArray<Int?> = [] // maps slot.rawValue -> dense index in `slots`

    public init(required: Set<ComponentTag>, excluded: Set<ComponentTag>) {
        self.requiredComponents = required
        self.excludedComponents = excluded
        // Build a query signature equivalent
        let reqSig = ComponentSignature(required)
        let exSig = ComponentSignature(excluded)
        self.signature = GroupSignature(contained: reqSig, excluded: exSig)
    }

    @inline(__always)
    private func ensureSparseCapacity(for raw: Int) {
        if raw >= sparseIndex.count {
            let newCount = max(raw + 1, sparseIndex.count * 2)
            sparseIndex.reserveCapacity(newCount)
            while sparseIndex.count < newCount { sparseIndex.append(nil) }
        }
    }

    @inline(__always)
    private func indexOf(_ slot: SlotIndex) -> Int? {
        let raw = slot.rawValue
        if raw < sparseIndex.count { return sparseIndex[raw] } else { return nil }
    }

    @inline(__always)
    private func insertSlot(_ slot: SlotIndex) {
        ensureSparseCapacity(for: slot.rawValue)
        guard sparseIndex[slot.rawValue] == nil else { return }
        slots.append(slot)
        sparseIndex[slot.rawValue] = slots.count - 1
    }

    @inline(__always)
    private func removeSlot(_ slot: SlotIndex) {
        let raw = slot.rawValue
        guard raw < sparseIndex.count, let idx = sparseIndex[raw] else { return }
        let lastIdx = slots.count - 1
        if idx != lastIdx {
            let moved = slots[lastIdx]
            slots[idx] = moved
            sparseIndex[moved.rawValue] = idx
        }
        _ = slots.popLast()
        sparseIndex[raw] = nil
    }

    @inline(__always)
    private func passes(_ slot: SlotIndex, in coordinator: Coordinator) -> Bool {
        let entitySignature = coordinator.entitySignatures[slot.index]
        return signature.contained.isSubset(of: entitySignature)
        && signature.excluded.isDisjoint(with: entitySignature)
    }

    public func rebuild(in coordinator: Coordinator) {
        // Choose the smallest required component array as base
        var baseArray: AnyComponentArray? = nil
        var minCount = Int.max
        for tag in requiredComponents {
            if let arr = coordinator.pool.components[tag] {
                let c = arr.componentsToEntites.count
                if c < minCount { minCount = c; baseArray = arr }
            } else {
                // No entities can match if a required array is missing
                slots.removeAll(keepingCapacity: true)
                return
            }
        }
        guard let base = baseArray else {
            // No required components: empty by definition
            slots.removeAll(keepingCapacity: true)
            return
        }
        // Rebuild slots from scratch
        slots.removeAll(keepingCapacity: true)
        // Reset sparse index to a reasonable size (optional growth later)
        sparseIndex.removeAll(keepingCapacity: false)
        for slot in base.componentsToEntites {
            if passes(slot, in: coordinator) { insertSlot(slot) }
        }
    }

    public func onComponentAdded(_ tag: ComponentTag, entity: Entity.ID, in coordinator: Coordinator) {
        // Only react if tag is relevant
        if !(requiredComponents.contains(tag) || excludedComponents.contains(tag)) { return }
        let slot = entity.slot
        if passes(slot, in: coordinator) {
            insertSlot(slot)
        } else {
            // If became invalid due to excluded, ensure removal
            removeSlot(slot)
        }
    }

    public func onWillRemoveComponent(_ tag: ComponentTag, entity: Entity.ID, in coordinator: Coordinator) {
        if !(requiredComponents.contains(tag) || excludedComponents.contains(tag)) { return }
        let slot = entity.slot
        // If removing a required component, membership must be dropped
        if requiredComponents.contains(tag) {
            removeSlot(slot)
            return
        }
        // If removing an excluded component, entity might become valid
        if excludedComponents.contains(tag) {
            if passes(slot, in: coordinator) { insertSlot(slot) } else { removeSlot(slot) }
        }
    }

    @usableFromInline
    func acquire(in signature: inout ComponentSignature) throws(GroupAcquireError) {
    }

    @usableFromInline
    func release(from signature: inout ComponentSignature) {
    }

    public func slotsSlice(in pool: inout ComponentPool) -> ArraySlice<SlotIndex> {
        return slots[...]
    }
}
