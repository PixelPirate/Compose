import Foundation

@usableFromInline
struct Groups {
    @usableFromInline
    final class Storage {
        @usableFromInline
        var groups: [GroupSignature: any GroupProtocol]

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
    mutating func add(_ group: some GroupProtocol, in pool: inout ComponentPool) {
        if !isKnownUniquelyReferenced(&storage) {
            storage = storage.copy()
        }
        storage.groups[group.signature] = group
        group.rebuild(in: &pool)
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
        return pool.components[group.primary]?.componentsToEntites[..<group.size]
    }

    @usableFromInline
    mutating func remove(_ signature: QuerySignature) {
        if !isKnownUniquelyReferenced(&storage) {
            storage = storage.copy()
        }
        let groupSignature = GroupSignature(signature)
        storage.groups.removeValue(forKey: groupSignature)
    }

    @usableFromInline
    func onComponentAdded(_ tag: ComponentTag, entity: Entity.ID, in pool: inout ComponentPool) {
        for group in storage.groups.values {
            group.onComponentAdded(tag, entity: entity, in: &pool)
        }
    }

    @usableFromInline
    func onWillRemoveComponent(_ tag: ComponentTag, entity: Entity.ID, in pool: inout ComponentPool) {
        for group in storage.groups.values {
            group.onWillRemoveComponent(tag, entity: entity, in: &pool)
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

// MARK: - SparseSet helpers for grouping (swap & index helpers)

extension SparseSet {
    /// Returns the dense index for the given slot if present.
    @inlinable @inline(__always)
    internal func denseIndex(for slot: SlotIndex) -> Int? {
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
        // This mirrors how withBuffer is implemented internally.
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
    func rebuild(in pool: inout ComponentPool)
    func onComponentAdded(_ tag: ComponentTag, entity: Entity.ID, in pool: inout ComponentPool)
    func onWillRemoveComponent(_ tag: ComponentTag, entity: Entity.ID, in pool: inout ComponentPool)

    var signature: GroupSignature { get }

    var size: Int { get }
    var primary: ComponentTag { get }
}

/// Global registry of which component is already owned by which group (to avoid conflicting orderings).
nonisolated(unsafe) private var _ownedTags = ComponentSignature()

/// A high-performance "owned group" that packs all entities matching the required signature
/// into a contiguous prefix of the primary component's dense storage.
public final class Group<each Owned: Component>: GroupProtocol {
    // All owned tags, including Primary and the rest of the pack
    public private(set) var primary: ComponentTag
    private let owned: Set<ComponentTag>
    public let ownedSignature: ComponentSignature
    public let signature: GroupSignature

    /// Contains owned, backstage and excluded components.
    public let fullSignature: ComponentSignature // TODO: This is incorrect. E.g.: "Own A, B, Exclude X, Y" and "Own X, Y, Exclude A, B" must both be supported.

    // Membership filter (derived from a Query or passed explicitly)
    private let backstageSignature: ComponentSignature
    private let excludeSignature: ComponentSignature
    private let backstageComponents: Set<ComponentTag>
    private let excludedComponents: Set<ComponentTag>
    private let query: Query<repeat each Owned>

    struct AcquireError: Error {
    }

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
        owned = result
        ownedSignature = ComponentSignature(owned)
        backstageSignature = query.signature
        excludeSignature = query.excludedSignature
        backstageComponents = query.backstageComponents
        excludedComponents = query.excludedComponents
        fullSignature = query.signature.union(query.excludedSignature)
        signature = GroupSignature(query.querySignature)
    }
    
    public convenience init(@QueryBuilder query: () -> BuiltQuery<repeat each Owned>) {
        self.init(query: query().composite)
    }

    func acquire() throws(AcquireError) {
        guard _ownedTags.isDisjoint(with: ownedSignature) else {
            throw AcquireError()
        }
        _ownedTags.formUnion(ownedSignature)
    }

    deinit {
        _ownedTags.remove(ownedSignature)
    }

    // Helper to verify if slot has all owned and backstage components for inclusion.
    @inline(__always)
    private func hasRequired(slot: SlotIndex, in pool: ComponentPool) -> Bool {
        for tag in owned {
            if pool.components[tag]?.entityToComponents[slot.rawValue] == nil {
                return false
            }
        }
        for tag in backstageComponents {
            if pool.components[tag]?.entityToComponents[slot.rawValue] == nil {
                return false
            }
        }
        return true
    }

    // TODO: Give this an Query in the init. We need the included/excluded beside the owned.
    // E.g.:
    /*
     Group<Transform, Renderer>(with: Material.self, not: Debug.self)
     Here we do not want to have ALL entities with Transform and Renderer be sorted to the top.
     We only want the ones which fully match the query.


     you still need a designated “primary” to derive the permutation and then apply that permutation to all other owned components in lock-step. That’s exactly how EnTT does it internally: one storage is the ordering source, and the others mirror its permutation.
     */

    /// Build (or rebuild) the contiguous partition for this group.
    /// This partitions the primary component's dense storage so that all matching entities are in [0 ..< size).
    public func rebuild(in pool: inout ComponentPool) {
        // Dynamically select the primary as the smallest owned storage to minimize scan/swaps
        var selectedPrimary: ComponentTag? = nil
        var minCount: Int = .max
        for tag in owned {
            if let arr = pool.components[tag] {
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

        // Pre-resolve membership maps for required (owned + backstage) and excluded components
        var requiredMaps: [ContiguousArray<Array.Index?>] = []
        var excludedMaps: [ContiguousArray<Array.Index?>] = []

        // Collect maps for all owned components (must be present)
        for tag in owned {
            guard let arr = pool.components[tag] else { return }
            requiredMaps.append(arr.entityToComponents)
        }
        // Collect maps for all backstage components (also required)
        for tag in backstageComponents {
            guard let arr = pool.components[tag] else { return }
            requiredMaps.append(arr.entityToComponents)
        }
        // Collect maps for all excluded components (optional presence; if present, entity is excluded)
        for tag in excludedComponents {
            if let arr = pool.components[tag] {
                excludedMaps.append(arr.entityToComponents)
            }
        }

        @inline(__always)
        func passes(_ slot: SlotIndex) -> Bool {
            let raw = slot.rawValue
            for map in requiredMaps { if map[raw] == nil { return false } }
            for map in excludedMaps { if map[raw] != nil { return false } }
            return true
        }

        // Access primary storage
        guard var primaryArray = pool.components[primary] else { return }

        // Find the concrete primary owned type and run the partition on it
        var handledPrimary = false
        for ownedComponentType in repeat (each Owned).QueriedComponent.self {
            if ownedComponentType.componentTag != self.primary { continue }
            handledPrimary = true

            // 1) Partition primary in a single pass and record swaps
            var swapLog: [(from: Int, to: Int, slotAtFrom: SlotIndex)] = []

            primaryArray._withMutableSparseSet(ownedComponentType) { primarySet in
                let total = primarySet.count
                var write = 0

                // Single-pass partition
                var read = 0
                while read < total {
                    let slot = primarySet.keys[read]
                    if passes(slot) {
                        if read != write {
                            // Record the slot at 'read' before swapping, so we can mirror the move
                            let slotAtFrom = primarySet.keys[read]
                            primarySet.swapDenseAt(read, write)
                            swapLog.append((from: read, to: write, slotAtFrom: slotAtFrom))
                        }
                        write &+= 1
                    }
                    read &+= 1
                }
                self.size = write
            }

            // 2) Mirror the same swaps to all other owned storages in a separate pass
            if !swapLog.isEmpty {
                for otherOwnedType in repeat (each Owned).QueriedComponent.self {
                    let tag = otherOwnedType.componentTag
                    if tag == self.primary { continue }
                    guard var otherArray = pool.components[tag] else { continue }

                    otherArray._withMutableSparseSet(otherOwnedType) { otherSet in
                        // Replay the swaps on the other set
                        for (from, to, slotAtFrom) in swapLog {
                            // Find where the entity at 'slotAtFrom' currently is in 'otherSet'
                            if let denseIndex = otherSet.denseIndex(for: slotAtFrom) {
                                // Move it to 'to' to mirror primary
                                if denseIndex != to {
                                    otherSet.swapDenseAt(denseIndex, to)
                                }
                            }
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
    public func onComponentAdded(_ tag: ComponentTag, entity: Entity.ID, in pool: inout ComponentPool) {
        // Only proceed if the added tag is part of this group's owned set and primary exists
        guard fullSignature.contains(tag), var primaryArray = pool.components[primary] else { return }

        // Find the concrete primary owned type
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

                        for otherOwnedType in repeat (each Owned).QueriedComponent.self {
                            if otherOwnedType.componentTag == self.primary { continue }
                            guard var otherArray = pool.components[otherOwnedType.componentTag] else { continue }
                            otherArray._withMutableSparseSet(otherOwnedType) { otherSet in
                                if let ai = otherSet.denseIndex(for: aSlot) {
                                    otherSet.swapDenseAt(ai, last)
                                }
                            }
                        }

                        size = last
                    }
                } else {
                    // If entity matches after addition and is not in packed prefix, swap it in
                    if pool.matches(slot: entity.slot, query: query), idx >= size {
                        let insertIndex = size
                        let aSlot = entity.slot

                        primarySet.swapDenseAt(idx, insertIndex)

                        for otherOwnedType in repeat (each Owned).QueriedComponent.self {
                            if otherOwnedType.componentTag == self.primary { continue }
                            guard var otherArray = pool.components[otherOwnedType.componentTag] else { continue }
                            otherArray._withMutableSparseSet(otherOwnedType) { otherSet in
                                if let ai = otherSet.denseIndex(for: aSlot) {
                                    otherSet.swapDenseAt(ai, insertIndex)
                                }
                            }
                        }

                        size &+= 1
                    }
                }
            }
            break
        }
    }

    /// Incremental hook to be called when a component is **removed** from an entity.
    /// If the entity was part of the group, it is swapped out of the packed prefix.
    public func onWillRemoveComponent(_ tag: ComponentTag, entity: Entity.ID, in pool: inout ComponentPool) {
        guard self.fullSignature.contains(tag) else { return }
        // Primary must exist to reorder
        guard var primaryArray = pool.components[primary] else { return }

        // Find the concrete primary owned type
        for ownedComponentType in repeat (each Owned).QueriedComponent.self {
            if ownedComponentType.componentTag != self.primary { continue }
            primaryArray._withMutableSparseSet(ownedComponentType) { primarySet in
                guard let idx = primarySet.denseIndex(for: entity.slot) else { return }

                if excludedComponents.contains(tag) {
                    // If tag is excluded and entity is outside packed prefix,
                    // check if it becomes valid now and swap in if so
                    if idx >= size {
                        if hasRequired(slot: entity.slot, in: pool) {
                            let insertIndex = size
                            let aSlot = entity.slot

                            primarySet.swapDenseAt(idx, insertIndex)

                            for otherOwnedType in repeat (each Owned).QueriedComponent.self {
                                if otherOwnedType.componentTag == self.primary { continue }
                                guard var otherArray = pool.components[otherOwnedType.componentTag] else { continue }
                                otherArray._withMutableSparseSet(otherOwnedType) { otherSet in
                                    if let ai = otherSet.denseIndex(for: aSlot) {
                                        otherSet.swapDenseAt(ai, insertIndex)
                                    }
                                }
                            }

                            size &+= 1
                        }
                    }
                } else if owned.contains(tag) || backstageComponents.contains(tag) {
                    // If tag is owned or backstage and entity is inside packed prefix,
                    // it will no longer match, so swap it out
                    if idx < size {
                        let last = size &- 1
                        let aSlot = primarySet.keys[idx]

                        primarySet.swapDenseAt(idx, last)

                        for otherOwnedType in repeat (each Owned).QueriedComponent.self {
                            if otherOwnedType.componentTag == self.primary { continue }
                            guard var otherArray = pool.components[otherOwnedType.componentTag] else { continue }
                            otherArray._withMutableSparseSet(otherOwnedType) { otherSet in
                                if let ai = otherSet.denseIndex(for: aSlot) {
                                    otherSet.swapDenseAt(ai, last)
                                }
                            }
                        }

                        size = last
                    }
                }
            }
            break
        }
    }

    /// Typed convenience.
    @inlinable @inline(__always)
    public func onComponentAdded<C: Component>(_ type: C.Type, entity: Entity.ID, in pool: inout ComponentPool) {
        onComponentAdded(C.componentTag, entity: entity, in: &pool)
    }

    /// Typed convenience.
    @inlinable @inline(__always)
    public func onWillRemoveComponent<C: Component>(_ type: C.Type, entity: Entity.ID, in pool: inout ComponentPool) {
        onWillRemoveComponent(C.componentTag, entity: entity, in: &pool)
    }
}

