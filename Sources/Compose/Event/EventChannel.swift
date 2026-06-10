@usableFromInline
final class NewChannel<E: Event> {
    @usableFromInline
    internal var events: ContiguousArray<E> = []

    @usableFromInline
    internal var back: Range<ContiguousArray.Index> = 0..<0
    @usableFromInline
    internal var current: Range<ContiguousArray.Index> = 0..<0
    @usableFromInline
    internal var live: Range<ContiguousArray.Index> = 0..<0

    @usableFromInline
    internal var eventIDs: Range<UInt64> = 0..<0

    @usableFromInline
    internal var retention: Retention = .doubleBuffered

    public enum Retention {
        case doubleBuffered
        case unrestricted
    }

    @inlinable @inline(__always)
    func send(_ event: E) {
        events.append(event)
    }

    @inlinable @inline(__always)
    func read(nextRead: inout UInt64) -> ArraySlice<E> {
        guard !live.isEmpty else {
            nextRead = eventIDs.upperBound
            return ArraySlice()
        }

        // Determine the lowest matching and available event ID.
        let startCount = max(nextRead, eventIDs.lowerBound)
        // Calculate array offset of event ID.
        let offset = Int(startCount - eventIDs.lowerBound)

        nextRead = eventIDs.upperBound

        guard live.contains(offset) else {
            return ArraySlice()
        }

        return events[offset..<live.upperBound]
    }

    @inlinable @inline(__always)
    func drain() -> ArraySlice<E> {
        let slice = events[live]
        eventIDs = (eventIDs.lowerBound+UInt64(live.count))..<eventIDs.upperBound
        back = live.upperBound..<live.upperBound
        current = live.upperBound..<live.upperBound
        live = live.upperBound..<live.upperBound
        return slice
    }

    @inlinable @inline(__always)
    func insertInFlightEvents() {
        let new = events.count - (live.upperBound - 1)
        current = current.lowerBound..<events.count
        live = live.lowerBound..<events.count
        eventIDs = eventIDs.lowerBound..<eventIDs.upperBound+UInt64(new)
    }

    @inlinable @inline(__always)
    func clear() {
        events.removeAll(keepingCapacity: true)
        eventIDs = (eventIDs.lowerBound+UInt64(live.count))..<eventIDs.upperBound
        back = 0..<0
        current = 0..<0
        live = 0..<0
    }

    @inlinable @inline(__always)
    func finishFrame() {
        precondition(live.count == events.count)
        guard retention == .doubleBuffered else { return }
        // Move events from previous frame (`back`) out.
        events[0...] = events[current]
        events.removeSubrange(current.count...)
        eventIDs = (eventIDs.lowerBound+UInt64(back.count))..<eventIDs.upperBound
        back = 0..<events.count
        current = events.count..<events.count
        live = 0..<events.count
    }
}

@usableFromInline
final class EventChannel<E: Event> {
    @usableFromInline
    internal var current: ContiguousArray<E> = []
    @usableFromInline
    internal var pending: ContiguousArray<E> = []

    @usableFromInline
    internal var currentStart: UInt64 = 0
    @usableFromInline
    internal var currentEnd: UInt64 = 0

    @inlinable @inline(__always)
    func prepare() {
        current.append(contentsOf: pending)
        currentEnd &+= UInt64(pending.count)
        pending.removeAll(keepingCapacity: true)
    }

    @inlinable @inline(__always)
    func clear() {
        current.removeAll(keepingCapacity: true)
        swap(&current, &pending)
        currentStart = currentEnd
        currentEnd &+= UInt64(current.count)
    }

    @inlinable @inline(__always)
    func send(_ event: E) {
        pending.append(event)
    }

    @inlinable @inline(__always)
    func read(state: inout EventReaderState<E>) -> ArraySlice<E> {
        if current.isEmpty {
            state.lastRead = currentEnd
            return []
        }
        let startCount = max(state.lastRead, currentStart)
        let offset = Int(startCount &- currentStart)
        state.lastRead = currentEnd
        if offset >= current.count {
            return []
        }
        return current[offset...]
    }

    @inlinable @inline(__always)
    func drain() -> [E] {
        if current.isEmpty {
            return []
        }
        let drained = Array(current)
        current.removeAll(keepingCapacity: true)
        currentStart = currentEnd
        return drained
    }
}
