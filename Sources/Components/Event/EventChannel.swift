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
        let safeStart = max(startCount, currentStart)
        let offset = Int(safeStart &- currentStart)
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
