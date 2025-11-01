public struct QueryContext: QueryContextConvertible, Sendable {
    @usableFromInline
    nonisolated(unsafe) internal var coordinator: Coordinator

    @usableFromInline
    init(coordinator: Coordinator) {
        self.coordinator = coordinator
    }

    @inlinable @inline(__always)
    public func resource<R>(_ type: R.Type = R.self) -> R {
        coordinator.resource(type)
    }

    @inlinable @inline(__always)
    public subscript<R>(resource resourceType: sending R.Type = R.self) -> R {
        @inlinable @inline(__always)
        _read {
            yield coordinator[resource: resourceType]
        }
        @inlinable @inline(__always)
        nonmutating set {
            coordinator[resource: resourceType] = newValue
        }
    }

    @inlinable @inline(__always)
    public func eventWriter<E: Event>(_ type: E.Type = E.self) -> EventWriter<E> {
        coordinator.eventWriter(type)
    }

    @inlinable @inline(__always)
    public func send<E: Event>(_ event: E) {
        coordinator.sendEvent(event)
    }

    @inlinable @inline(__always)
    public func readEvents<E: Event>(_ type: E.Type = E.self, state: inout EventReaderState<E>) -> EventSequence<E> {
        coordinator.readEvents(type, state: &state)
    }

    @inlinable @inline(__always)
    public func drainEvents<E: Event>(_ type: E.Type = E.self) -> [E] {
        coordinator.drainEvents(type)
    }

    @inlinable @inline(__always)
    public var queryContext: QueryContext {
        _read {
            yield self
        }
    }
}

extension Coordinator: QueryContextConvertible {
    @inlinable @inline(__always)
    public var queryContext: QueryContext {
        _read {
            yield QueryContext(coordinator: self)
        }
    }
}

public protocol QueryContextConvertible {
    @inlinable @inline(__always)
    var queryContext: QueryContext { get }
}
