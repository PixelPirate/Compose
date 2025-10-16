import Foundation

@usableFromInline
struct Groups {
    final class Storage {
        var groups: [any GroupProtocol]

        func copy() -> Storage {
            Storage(groups: groups)
        }

        init(groups: [any GroupProtocol] = []) {
            self.groups = groups
        }
    }

    private var storage = Storage()

    mutating func add(_ group: some GroupProtocol, in pool: inout ComponentPool) {
        if !isKnownUniquelyReferenced(&storage) {
            storage = storage.copy()
        }
        storage.groups.append(group)
        group.rebuild(in: &pool)
    }

    @usableFromInline
    func onComponentAdded(_ tag: ComponentTag, entity: Entity.ID, in pool: inout ComponentPool) {
        for group in storage.groups {
            group.onComponentAdded(tag, entity: entity, in: &pool)
        }
    }

    @usableFromInline
    func onComponentRemoved(_ tag: ComponentTag, entity: Entity.ID, in pool: inout ComponentPool) {
        for group in storage.groups {
            group.onComponentRemoved(tag, entity: entity, in: &pool)
        }
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
        let typed = base as! ComponentArrayBox<C>
        var ref = typed.base
        let result = try body(&ref)
        typed.base = ref
        return result
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

protocol GroupProtocol {
    func rebuild(in pool: inout ComponentPool)
    func onComponentAdded(_ tag: ComponentTag, entity: Entity.ID, in pool: inout ComponentPool)
    func onComponentRemoved(_ tag: ComponentTag, entity: Entity.ID, in pool: inout ComponentPool)
}

/// Global registry of which component is already owned by which group (to avoid conflicting orderings).
nonisolated(unsafe) private var _ownedTags = ComponentSignature()

/// A high-performance "owned group" that packs all entities matching the required signature
/// into a contiguous prefix of the primary component's dense storage.
public final class Group<each Owned: Component>: GroupProtocol {
    // All owned tags, including Primary and the rest of the pack
    private let primary: ComponentTag
    private let owned: Set<ComponentTag>
    public let ownedSignature: ComponentSignature

    /// Contains owned, backstage and excluded components.
    public let fullSignature: ComponentSignature

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
            result.insert(owned.componentTag)
            if first {
                first = false
                prim = owned.componentTag
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
        // Operate on primary storage only; mirror swaps to others
        guard var primaryArray = pool.components[primary] else { return }

        // Find the concrete primary owned type
        var handledPrimary = false
        for ownedComponentType in repeat (each Owned).self {
            if ownedComponentType.componentTag != self.primary { continue }
            handledPrimary = true
            primaryArray._withMutableSparseSet(ownedComponentType) { primarySet in
                var write = 0
                let total = primarySet.count
                while write < total {
                    let slotAtWrite = primarySet.keys[write]
                    if pool.matches(slot: slotAtWrite, query: query) {
                        write &+= 1
                    } else {
                        var read = write &+ 1
                        var foundIndex: Int? = nil
                        while read < total {
                            let slot = primarySet.keys[read]
                            if pool.matches(slot: slot, query: query) {
                                foundIndex = read
                                break
                            }
                            read &+= 1
                        }
                        if let j = foundIndex {
                            // Capture entity slots before swapping in primary
                            let bSlot = primarySet.keys[j]

                            // Swap in primary
                            primarySet.swapDenseAt(write, j)

                            // Mirror to all other owned storages using packed-prefix target index
                            for otherOwnedType in repeat (each Owned).self {
                                if otherOwnedType.componentTag == self.primary { continue }
                                guard var otherArray = pool.components[otherOwnedType.componentTag] else { continue }
                                otherArray._withMutableSparseSet(otherOwnedType) { otherSet in
                                    // Move the matching entity `b` into the packed position `write`
                                    if let bi = otherSet.denseIndex(for: bSlot) {
                                        otherSet.swapDenseAt(bi, write)
                                    }
                                }
                            }

                            write &+= 1
                        } else {
                            break
                        }
                    }
                }
                self.size = write
            }
            break
        }
        if !handledPrimary { return }
    }

    /// Incremental hook to be called when a component is **added** to an entity.
    /// If the entity now matches the group, it is swapped into the packed prefix.
    public func onComponentAdded(_ tag: ComponentTag, entity: Entity.ID, in pool: inout ComponentPool) {
        // Only proceed if the added tag is part of this group's owned set and primary exists
        guard fullSignature.contains(tag), var primaryArray = pool.components[primary] else { return }

        // Find the concrete primary owned type
        for ownedComponentType in repeat (each Owned).self {
            if ownedComponentType.componentTag != self.primary { continue }
            primaryArray._withMutableSparseSet(ownedComponentType) { primarySet in
                guard let idx = primarySet.denseIndex(for: entity.slot) else { return }
                if pool.matches(slot: entity.slot, query: query) && idx >= size {
                    // Capture slots before swap in primary
                    let bSlot = primarySet.keys[size]

                    // Swap in primary
                    primarySet.swapDenseAt(idx, size)

                    // Mirror to other owned storages using packed-prefix target index
                    for otherOwnedType in repeat (each Owned).self {
                        if otherOwnedType.componentTag == self.primary { continue }
                        guard var otherArray = pool.components[otherOwnedType.componentTag] else { continue }
                        otherArray._withMutableSparseSet(otherOwnedType) { otherSet in
                            // Move the added matching entity (slot `b`) into the packed position `size`
                            if let bi = otherSet.denseIndex(for: bSlot) {
                                otherSet.swapDenseAt(bi, size)
                            }
                        }
                    }

                    size &+= 1
                }
            }
            break
        }
    }

    /// Incremental hook to be called when a component is **removed** from an entity.
    /// If the entity was part of the group, it is swapped out of the packed prefix.
    public func onComponentRemoved(_ tag: ComponentTag, entity: Entity.ID, in pool: inout ComponentPool) {
        guard self.fullSignature.contains(tag) else { return }
        // Primary must exist to reorder
        guard var primaryArray = pool.components[primary] else { return }

        // Find the concrete primary owned type
        for ownedComponentType in repeat (each Owned).self {
            if ownedComponentType.componentTag != self.primary { continue }
            primaryArray._withMutableSparseSet(ownedComponentType) { primarySet in
                guard let idx = primarySet.denseIndex(for: entity.slot) else { return }
                if idx < size && !pool.matches(slot: entity.slot, query: query) {
                    let last = size &- 1
                    // Capture slots before swap in primary
                    let aSlot = primarySet.keys[idx]

                    // Swap in primary
                    primarySet.swapDenseAt(idx, last)

                    // Mirror to other owned storages using packed-prefix target index
                    for otherOwnedType in repeat (each Owned).self {
                        if otherOwnedType.componentTag == self.primary { continue }
                        guard var otherArray = pool.components[otherOwnedType.componentTag] else { continue }
                        otherArray._withMutableSparseSet(otherOwnedType) { otherSet in
                            // Move the removed entity (slot `a`) out of the packed prefix by swapping with `last`
                            if let ai = otherSet.denseIndex(for: aSlot) {
                                otherSet.swapDenseAt(ai, last)
                            }
                        }
                    }

                    size = last
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
    public func onComponentRemoved<C: Component>(_ type: C.Type, entity: Entity.ID, in pool: inout ComponentPool) {
        onComponentRemoved(C.componentTag, entity: entity, in: &pool)
    }
}
