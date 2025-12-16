public struct RemovedComponentArray {
    @usableFromInline
    internal var storage: SparseSet<ComponentTicks, SlotIndex>

    @inlinable @inline(__always)
    public init() {
        self.storage = SparseSet<ComponentTicks, SlotIndex>()
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
            storage.storage.mutablePointer(for: denseIndex).pointee.markRemoved(at: tick)
            return
        }

        storage.append(ComponentTicks(added: .min, changed: .min, removed: tick), to: slot)
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
