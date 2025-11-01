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
