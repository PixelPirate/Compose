public protocol OptionalQueriedComponent {
    associatedtype Queried: Component
}

extension Optional: Component, ComponentResolving where Wrapped: Component {
    public typealias QueriedComponent = Wrapped
    public static var componentTag: ComponentTag { Wrapped.componentTag }

    @inlinable @inline(__always)
    public static func makeResolved(access: TypedAccess<Self>, entityID: Entity.ID) -> Optional<Wrapped> {
        access[optional: entityID]
    }

    @inlinable @inline(__always)
    public static func makeReadOnlyResolved(access: TypedAccess<Self>, entityID: Entity.ID) -> Optional<Wrapped> {
        access[optional: entityID]
    }

    @inlinable @inline(__always)
    public static func makeResolvedDense(access: TypedAccess<Self>, denseIndex: Int, entityID: Entity.ID) -> Optional<Wrapped> {
        access[optional: entityID]
    }

    @inlinable @inline(__always)
    public static func makeReadOnlyResolvedDense(access: TypedAccess<Self>, denseIndex: Int, entityID: Entity.ID) -> Optional<Wrapped> {
        access[optional: entityID]
    }
}

extension Optional: OptionalQueriedComponent where Wrapped: Component {
    public typealias Queried = Wrapped
}
