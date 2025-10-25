//
//  WithEntityID.swift
//  Components
//
//  Created by Patrick Horlebein (extern) on 10.10.25.
//

public struct WithEntityID: Component, Sendable {
    public static var componentTag: ComponentTag { ComponentTag(rawValue: -1) }
    public typealias ResolvedType = Entity.ID
    public typealias ReadOnlyResolvedType = Entity.ID
    public typealias QueriedComponent = Never

    @inlinable @inline(__always)
    public static var needsEntityID: Bool { true }

    public init() {}

    @inlinable @inline(__always)
    public static func makeResolved(access: TypedAccess<Self>, entityID: Entity.ID) -> ResolvedType {
        entityID
    }

    @inlinable @inline(__always)
    public static func makeReadOnlyResolved(access: TypedAccess<Self>, entityID: Entity.ID) -> ResolvedType {
        entityID
    }

    @inlinable @inline(__always)
    public static func makeResolvedDense(access: TypedAccess<Self>, denseIndex: Int, entityID: Entity.ID) -> ResolvedType {
        entityID
    }

    @inlinable @inline(__always)
    public static func makeReadOnlyResolvedDense(access: TypedAccess<Self>, denseIndex: Int, entityID: Entity.ID) -> ResolvedType {
        entityID
    }
}
