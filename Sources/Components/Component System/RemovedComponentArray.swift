struct RemovedComponentArray {
    @usableFromInline
    internal var storage: SparseSet<UInt64, SlotIndex> = SparseSet()

    @inlinable @inline(__always)
    var indices: SlotsSpan<ContiguousArray.Index, SlotIndex> { storage.slots.view }

    @inlinable @inline(__always)
    var ticks: MutableContiguousSpan<UInt64> { storage.view }

    @inlinable @inline(__always)
    var isEmpty: Bool { storage.count == 0 }

    @inlinable @inline(__always)
    mutating func recordRemoval(of slot: SlotIndex, at tick: UInt64) {
        let denseIndex = storage.componentIndex(slot)
        if denseIndex == .notFound {
            storage.append(tick, to: slot)
        } else {
            storage.storage.mutablePointer(at: denseIndex).pointee = tick
        }
    }

    @inlinable @inline(__always)
    mutating func remove(_ slot: SlotIndex) {
        storage.remove(slot)
    }

    @inlinable @inline(__always)
    mutating func prune(olderThan tick: UInt64) {
        var denseIndex = 0
        while denseIndex < storage.count {
            let currentTick = storage.storage.mutablePointer(at: denseIndex).pointee
            if currentTick < tick {
                let slot = storage.keys[denseIndex]
                storage.remove(slot)
            } else {
                denseIndex &+= 1
            }
        }
    }
}

