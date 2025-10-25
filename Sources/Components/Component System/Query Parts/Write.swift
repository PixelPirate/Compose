//
//  WritableComponent.swift
//  Components
//
//  Created by Patrick Horlebein (extern) on 10.10.25.
//


@usableFromInline
protocol WritableComponent: Component {
    associatedtype Wrapped: Component
}

@usableFromInline
protocol DenseWritableComponent: WritableComponent {
    @inlinable @inline(__always)
    static func _makeResolvedDense(pointer: UnsafeMutablePointer<Wrapped>) -> Self
}

@dynamicMemberLookup
public struct Write<C: Component>: WritableComponent, Sendable {
    public static var componentTag: ComponentTag { C.componentTag }

    public typealias Wrapped = C

    @usableFromInline
    nonisolated(unsafe) let access: SingleTypedAccess<C>

    @inlinable @inline(__always)
    init(access: SingleTypedAccess<C>) {
        self.access = access
    }

    @inlinable @inline(__always)
    public subscript<R>(dynamicMember keyPath: WritableKeyPath<C, R>) -> R {
        _read {
            yield access.value[keyPath: keyPath]
        }
        nonmutating _modify {
            yield &access.value[keyPath: keyPath]
        }
    }
}

extension Write: ComponentResolving {
    public typealias ResolvedType = Write<Wrapped>
    public typealias ReadOnlyResolvedType = Wrapped
    public typealias QueriedComponent = Wrapped

    @inlinable @inline(__always)
    public static func makeResolved(access: TypedAccess<Self>, entityID: Entity.ID) -> Write<Wrapped> {
        Write<Wrapped>(access: access.access(entityID))
    }

    @inlinable @inline(__always)
    public static func makeReadOnlyResolved(access: TypedAccess<Self>, entityID: Entity.ID) -> Wrapped {
        access[entityID]
    }

    @inlinable @inline(__always)
    public static func makeResolvedDense(access: TypedAccess<Self>, denseIndex: Int, entityID: Entity.ID) -> Write<Wrapped> {
        Write<Wrapped>(access: access.accessDense(denseIndex))
    }

    @inlinable @inline(__always)
    public static func makeReadOnlyResolvedDense(access: TypedAccess<Self>, denseIndex: Int, entityID: Entity.ID) -> Wrapped {
        access[dense: denseIndex]
    }
}

extension Write: DenseWritableComponent {
    @inlinable @inline(__always)
    static func _makeResolvedDense(pointer: UnsafeMutablePointer<Wrapped>) -> Write<Wrapped> {
        Write<Wrapped>(access: SingleTypedAccess(buffer: pointer))
    }
}
