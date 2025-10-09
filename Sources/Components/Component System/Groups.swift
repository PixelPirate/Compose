
import Foundation

// MARK: - SparseSet helpers for grouping (swap & index helpers)

extension SparseSet {
    /// Returns the dense index for the given slot if present.
    @inlinable @inline(__always)
    internal func denseIndex(for slot: SlotIndex) -> Int? {
        if slots.contains(index: slot) {
            // NOTE: SparseArray subscript is total; caller must ensure presence.
            return slots[slot]
        }
        return nil
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
    @inlinable @inline(__always)
    func _withComponentsToSlots<C: Component, R>(
        _ type: C.Type,
        _ body: (ContiguousArray<SlotIndex>) throws -> R
    ) rethrows -> R {
        let typed = base as! ComponentArrayBox<C>
        return try body(typed.componentsToEntites)
    }
}

// MARK: - Group

/// Global registry of which component is already owned by which group (to avoid conflicting orderings).
nonisolated(unsafe) private var _ownedTags = Set<ComponentTag>()

/// A high-performance "owned group" that packs all entities matching the required signature
/// into a contiguous prefix of the primary component's dense storage.
///
/// Ownership rule: Only one OwnedGroup may own a given component type at a time.
public final class OwnedGroup<Owned: Component> {
    /// Component tags that must be present on an entity to be part of the group (includes `Owned.componentTag`).
    private let required: Set<ComponentTag>

    /// Number of packed entities at the front of the primary component's storage.
    public private(set) var size: Int = 0

    /// Whether this group excludes any tags (future extension).
    private let excluded: Set<ComponentTag> = []

    public init<each Others: Component>(owning _: Owned.Type = Owned.self, requiring _: repeat (each Others).Type) {
        var r: Set<ComponentTag> = [Owned.componentTag]
        for other in repeat (each Others).self {
            // `Never` sentinel can be used by queries; ignore here if present.
            if other == (Never.self as! any Component.Type) { continue }
            r.insert(other.componentTag)
        }
        self.required = r
    }

    deinit {
        // Release ownership on drop.
        _ownedTags.remove(Owned.componentTag)
    }

    /// Acquire ownership for `Owned` if not already taken; call before building or mutating group.
    /// Returns false if another group already owns this component.
    @discardableResult
    public func tryAcquireOwnership() -> Bool {
        if _ownedTags.contains(Owned.componentTag) { return false }
        _ownedTags.insert(Owned.componentTag)
        return true
    }

    /// Build (or rebuild) the contiguous partition for this group.
    /// This partitions the primary component's dense storage so that all matching entities are in [0 ..< size).
    public func rebuild(in pool: inout ComponentPool) {
        if !_ownedTags.contains(Owned.componentTag) { _ = tryAcquireOwnership() }
        guard var ownedArray = pool.components[Owned.componentTag] else { return }
        // Prepare required arrays for quick membership checks.
        var otherArrays: [AnyComponentArray] = []
        otherArrays.reserveCapacity(required.count - 1)
        for tag in required where tag != Owned.componentTag {
            guard let arr = pool.components[tag] else {
                // Missing a required component entirely means no entities will match.
                self.size = 0
                return
            }
            otherArrays.append(arr)
        }

        // Partition the Owned sparse set.
        ownedArray._withMutableSparseSet(Owned.self) { set in
            var write = 0
            // Iterate dense indices and swap qualifying entities forward.
            let total = set.count
            while write < total {
                // Get slot for entity currently at `write` (after previous swaps).
                let slotAtWrite = set.keys[write]
                if _entityHasAll(slotAtWrite, arrays: otherArrays) {
                    // Already matches and in place; advance write.
                    write &+= 1
                } else {
                    // Find the next matching entity after `write`.
                    var read = write &+ 1
                    var foundIndex: Int? = nil
                    while read < total {
                        let slot = set.keys[read]
                        if _entityHasAll(slot, arrays: otherArrays) {
                            foundIndex = read
                            break
                        }
                        read &+= 1
                    }
                    if let j = foundIndex {
                        // Swap the found match into position `write`.
                        set.swapDenseAt(write, j)
                        write &+= 1
                    } else {
                        // No more matches.
                        break
                    }
                }
            }
            self.size = write
        }

        // Write back the possibly modified array
//        pool.components[Owned.componentTag] = ownedArray
    }

    /// Incremental hook to be called when a component is **added** to an entity.
    /// If the entity now matches the group, it is swapped into the packed prefix.
    public func onComponentAdded(_ tag: ComponentTag, entity: Entity.ID, in pool: inout ComponentPool) {
        // Quick filter: only care if the added tag is required by this group.
        if !required.contains(tag) { return }
        guard var ownedArray = pool.components[Owned.componentTag] else { return }

        // Build other arrays for membership checks.
        var otherArrays: [AnyComponentArray] = []
        otherArrays.reserveCapacity(required.count - 1)
        for t in required where t != Owned.componentTag {
            guard let arr = pool.components[t] else { return } // can't match yet
            otherArrays.append(arr)
        }

        // If entity matches all requirements, ensure it is within [0, size).
        ownedArray._withMutableSparseSet(Owned.self) { set in
            guard let idx = set.denseIndex(for: entity.slot) else { return }
            if _entityHasAll(entity.slot, arrays: otherArrays) && idx >= size {
                set.swapDenseAt(idx, size)
                size &+= 1
            }
        }
//        pool.components[Owned.componentTag] = ownedArray
    }

    /// Incremental hook to be called when a component is **removed** from an entity.
    /// If the entity was part of the group, it is swapped out of the packed prefix.
    public func onComponentRemoved(_ tag: ComponentTag, entity: Entity.ID, in pool: inout ComponentPool) {

        // If the removed tag is not required, the entity may still be in the group; quick check needed anyway.
        guard var ownedArray = pool.components[Owned.componentTag] else { return }

        // Build other arrays for membership checks (post-removal state).
        var otherArrays: [AnyComponentArray] = []
        otherArrays.reserveCapacity(required.count - 1)
        for t in required where t != Owned.componentTag {
            // If a required component is missing entirely, membership is impossible.
            guard let arr = pool.components[t] else { otherArrays.removeAll(keepingCapacity: true); break }
            otherArrays.append(arr)
        }

        ownedArray._withMutableSparseSet(Owned.self) { set in
            guard let idx = set.denseIndex(for: entity.slot) else { return }
            // If `idx` is inside the packed region and the entity no longer matches, swap it out.
            if idx < size && !_entityHasAll(entity.slot, arrays: otherArrays) {
                let last = size &- 1
                set.swapDenseAt(idx, last)
                size = last
            }
        }
//        pool.components[Owned.componentTag] = ownedArray
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

    /// Iterate over the tightly packed prefix of the primary component.
    /// Closure receives (Entity.ID, inout Owned). Other components can be accessed via `pool` as needed.
    @inlinable
    public func forEach(in pool: inout ComponentPool, _ body: (Entity.ID, inout Owned) -> Void) {
        guard var ownedArray = pool.components[Owned.componentTag] else { return }
        ownedArray._withMutableSparseSet(Owned.self) { set in
            // We need `inout Owned` at each dense index and the corresponding Entity.ID.
            // Entity.ID requires a generation, but underlying accessors index by slot only.
            // We'll construct an ID with generation 0 (safe for component access).
            for i in 0..<size {
                let slot = set.keys[i]
                var tmp = set[i]   // get component value
                // Pass as inout by writing back after closure (copy-in/out pattern).
                let id = Entity.ID(slot: slot, generation: 0)
                body(id, &tmp)
                set[i] = tmp
            }
        }
//        pool.components[Owned.componentTag] = ownedArray
    }

    // MARK: - Helpers

    @inlinable @inline(__always)
    internal func _entityHasAll(_ slot: SlotIndex, arrays: [AnyComponentArray]) -> Bool {
        for arr in arrays {
            // Check presence via entity->component dense index map
            if arr.entityToComponents[slot.rawValue] == nil { return false }
        }
        // Apply exclusions if any (future extension)
        return true
    }
}
