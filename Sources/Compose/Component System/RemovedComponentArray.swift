public struct RemovedComponentArray {
    @usableFromInline
    internal var storage: SparseSet<ComponentTicks, SlotIndex>
//    @usableFromInline
//    internal var destroyedEvents: RemovedEventBuffer // We currently do not track removals when entities get destroyed.

    @inlinable @inline(__always)
    init() {
        storage = SparseSet<ComponentTicks, SlotIndex>()
//        destroyedEvents = RemovedEventBuffer()
    }

    @inlinable @inline(__always)
    public func deallocate() {
        storage.deallocate()
    }

    @inlinable @inline(__always)
    mutating func ensureEntity(_ entityID: Entity.ID) {
        storage.ensureEntity(entityID.slot)
    }

    @inlinable @inline(__always)
    mutating func recordRemoval(of entityID: Entity.ID, at tick: UInt64) {
        let slot = entityID.slot
        let denseIndex = storage.componentIndex(slot)
        if denseIndex != .notFound {
            storage.storage.mutablePointer(for: denseIndex).pointee.markRemoved(at: tick, generation: entityID.generation)
            return
        }

        storage.append(ComponentTicks(removed: tick, generation: entityID.generation), to: slot)
//        destroyedEvents.record(slot: entityID.slot, generation: entityID.generation, tick: tick)
    }

    @inlinable @inline(__always)
    func isRemoved(_ entityID: Entity.ID, since lastRun: UInt64, upTo thisRun: UInt64) -> Bool {
        let denseIndex = storage.componentIndex(entityID.slot)
        guard denseIndex != . notFound else { return false }
        let ticks = storage.storage.pointer(for: denseIndex) .pointee
        guard ticks.removedGeneration == entityID.generation else { return false }
        return ticks.isRemoved(since: lastRun, upTo: thisRun)
    }

    @inlinable @inline(__always)
    mutating func remove(_ entityID: Entity.ID) {
        storage.remove(entityID.slot)
    }

    @inlinable @inline(__always)
    func withIndices<Result>(
        _ body: (SlotsSpan<ContiguousArray.Index, SlotIndex>, MutableContiguousSpan<ComponentTicks>) throws -> Result
    ) rethrows -> Result {
        try body(storage.slots.view, storage.storage.mutableView)
    }
}
