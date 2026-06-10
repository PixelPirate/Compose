public enum EventRetention {
    /// Retains the event for two frames, the frame in which it was send and the next frame.
    case doubleBuffered
    /// Retains the event indefinitely. Using this requires manually calling ``QueryContext/clearEvents(_:)``.
    case unrestricted
}

@usableFromInline
final class EventChannel<E: Event> {
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
    internal var retention: EventRetention = .doubleBuffered

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

        assert(eventIDs.count == live.upperBound)

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
        let new = events.count - live.upperBound
        current = current.lowerBound..<events.count
        live = live.lowerBound..<events.count
        eventIDs = eventIDs.lowerBound..<eventIDs.upperBound+UInt64(new)
        assert(eventIDs.count == events.count)
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
        insertInFlightEvents()
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
