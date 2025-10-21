//
//  OptionalWrite.swift
//  Components
//
//  Created by Patrick Horlebein (extern) on 10.10.25.
//

@dynamicMemberLookup
public struct OptionalWrite<C: Component>: WritableComponent, OptionalQueriedComponent, Sendable {
    public typealias Queried = C

    public static var componentTag: ComponentTag { C.componentTag }

    public typealias Wrapped = C

    @usableFromInline
    nonisolated(unsafe) let access: SingleTypedAccess<C>?

    @inlinable @inline(__always)
    init(access: SingleTypedAccess<C>?) {
        self.access = access
    }

    @inlinable @inline(__always)
    public subscript<R>(dynamicMember keyPath: WritableKeyPath<C, R>) -> R? {
        _read {
            yield access?.value[keyPath: keyPath]
        }
        nonmutating _modify {
            var value = access?.value[keyPath: keyPath]
            yield &value
            guard let newValue = value, let access else {
                if access != nil {
                    fatalError("Cannot write `nil` through an optional. Remove component through proper means like an command.")
                }
                return
            }
            access.value[keyPath: keyPath] = newValue
        }
    }
}

extension OptionalWrite: ComponentResolving {
    public typealias QueriedComponent = Wrapped

    @inlinable @inline(__always)
    public static func makeResolved(access: TypedAccess<Self>, entityID: Entity.ID) -> OptionalWrite<Wrapped> {
        OptionalWrite<Wrapped>(access: access.optionalAccess(entityID))
    }

    @inlinable @inline(__always)
    public static func makeReadOnlyResolved(access: TypedAccess<Self>, entityID: Entity.ID) -> Wrapped? {
        access[optional: entityID]
    }

    @inlinable @inline(__always)
    public static func makeResolvedDense(access: TypedAccess<Self>, denseIndex: Int, entityID: Entity.ID) -> OptionalWrite<Wrapped> {
        OptionalWrite<Wrapped>(access: access.optionalAccess(entityID))
    }

    @inlinable @inline(__always)
    public static func makeReadOnlyResolvedDense(access: TypedAccess<Self>, denseIndex: Int, entityID: Entity.ID) -> Wrapped? {
        access[optional: entityID]
    }
}
