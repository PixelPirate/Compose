public struct QueryContext: QueryContextConvertible, Sendable {
    @usableFromInline
    nonisolated(unsafe) internal var coordinator: Coordinator

    @usableFromInline
    internal let systemID: SystemID?

    @usableFromInline
    internal let lastRunTick: UInt64

    @usableFromInline
    init(coordinator: Coordinator, systemID: SystemID? = nil, lastRunTick: UInt64 = 0) {
        self.coordinator = coordinator
        self.systemID = systemID
        self.lastRunTick = lastRunTick
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
    public func resourceVersion<R>(_ type: R.Type = R.self) -> UInt64? {
        coordinator.resourceVersion(type)
    }

    @inlinable @inline(__always)
    public func makeResourceVersionSnapshot() -> Coordinator.ResourceVersionSnapshot {
        coordinator.makeResourceVersionSnapshot()
    }

    @inlinable @inline(__always)
    public func updatedResources(since snapshot: Coordinator.ResourceVersionSnapshot) -> [ResourceKey] {
        coordinator.updatedResources(since: snapshot)
    }

    @inlinable @inline(__always)
    public func resourceUpdated<R>(_ type: R.Type = R.self, since snapshot: Coordinator.ResourceVersionSnapshot) -> Bool {
        coordinator.resourceUpdated(type, since: snapshot)
    }

    @inlinable @inline(__always)
    public func resourceIfUpdated<R>(_ type: R.Type = R.self, since snapshot: Coordinator.ResourceVersionSnapshot) -> R? {
        coordinator.resourceIfUpdated(type, since: snapshot)
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
