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

        assert(eventIDs.count == live.count)

        // Determine the lowest matching and available event ID.
        let startEventID = max(nextRead, eventIDs.lowerBound)
        // Calculate array offset of event ID.
        // `startEventID - eventIDs.lowerBound` converts Event ID into an events index, we add `live.lowerBound` to account for drained events.
        let offset = ContiguousArray<E>.Index(startEventID - eventIDs.lowerBound) + live.lowerBound

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
        /*
         0 1 2 3 4 5 6 7 8 9 10  -> Count=11
         1 ^-     9       -^  1  := Live=1..<10
         Drained  Live        New
         */

        let drained = live.lowerBound
        let new = events.count - live.upperBound
        eventIDs = eventIDs.lowerBound..<eventIDs.upperBound+UInt64(new)
        current = current.lowerBound..<current.upperBound+new
        live = live.lowerBound..<live.upperBound+new
        assert(eventIDs.count == events.count - drained)
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
        assert(live.count == events.count - live.lowerBound) // The number of live events is equal to all events minus drained events.
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
