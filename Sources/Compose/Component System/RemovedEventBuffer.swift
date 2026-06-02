@usableFromInline
struct RemovedEvent: Sendable {
    @usableFromInline
    let slot: SlotIndex
    @usableFromInline
    let generation: UInt32
    @usableFromInline
    let tick: UInt64

    @inlinable @inline(__always)
    init(slot: SlotIndex, generation: UInt32, tick: UInt64) {
        self.slot = slot
        self.generation = generation
        self.tick = tick
    }
}

@usableFromInline
struct RemovedEventBuffer {
    @usableFromInline
    private(set) var events: ContiguousArray<RemovedEvent>

    @inlinable @inline(__always)
    init() {
        events = []
    }

    @inlinable @inline(__always)
    mutating func record(slot: SlotIndex, generation: UInt32, tick: UInt64) {
        events.append(RemovedEvent(slot: slot, generation: generation, tick: tick))
    }

    @inlinable @inline(__always)
    var isEmpty: Bool { events.isEmpty }

    @inlinable @inline(__always)
    func isRemoved(_ entityID: Entity.ID, since lastRun: UInt64, upTo thisRun: UInt64) -> Bool {
        for index in lowerBound(tick: lastRun)..<upperBound(tick: thisRun) {
            let event = events[index]
            if event.slot == entityID.slot, event.generation == entityID.generation {
                return true
            }
        }
        return false
    }

    @inlinable @inline(__always)
    func lowerBound(tick: UInt64) -> Int {
        var lo = 0
        var hi = events.count
        while lo < hi {
            let mid = (lo &+ hi) &>> 1
            if events[mid].tick <= tick {
                lo = mid &+ 1
            } else {
                hi = mid
            }
        }
        return lo
    }

    @inlinable @inline(__always)
    func upperBound(tick: UInt64) -> Int {
        var lo = 0
        var hi = events.count
        while lo < hi {
            let mid = (lo &+ hi) &>> 1
            if events[mid].tick <= tick {
                lo = mid &+ 1
            } else {
                hi = mid
            }
        }
        return lo
    }

    @inlinable @inline(__always)
    mutating func prune(before tick: UInt64) {
        let cutoff = lowerBound(tick: tick &- 1)
        if cutoff > 0 {
            events.removeFirst(cutoff)
        }
    }
}
