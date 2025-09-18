public struct Query<each T: Component> where repeat each T: ComponentResolving {
    /// These components will be used for selecting the correct archetype, but they will not be included in the query output.
    public let backstageComponents: Set<ComponentTag> // Or witnessComponents?

    public let excludedComponents: Set<ComponentTag>

    public func appending<U>(_ type: U.Type = U.self) -> Query<repeat each T, U> {
        Query<repeat each T, U>(backstageComponents: backstageComponents, excludedComponents: excludedComponents)
    }

    @inlinable @inline(__always)
    public func perform(_ coordinator: inout Coordinator, _ handler: (repeat (each T).ResolvedType) -> Void) {
        let entityIDs = coordinator.pool.entities(
            repeat (each T).InnerType.self,
            included: backstageComponents,
            excluded: excludedComponents
        )
        withTypedBuffers(&coordinator.pool) { (
            buffers: repeat (UnsafeMutableBufferPointer<(each T).InnerType>, [Entity.ID: Array.Index])
        ) in
            let accessors = (repeat TypedAccess(buffer: (each buffers).0, indices: (each buffers).1))
            for entityId in entityIDs {
                handler(repeat (each T).makeResolved(access: each accessors, entityID: entityId))
            }
        }
    }

    public func fetchAll(_ coordinator: inout Coordinator) -> [Entity.ID: (repeat (each T).InnerType)] {
        var result: [Entity.ID: (repeat (each T).InnerType)] = [:]
        let entityIDs = coordinator.pool.entities(
            repeat (each T).InnerType.self,
            included: backstageComponents,
            excluded: excludedComponents
        )
        withTypedBuffers(&coordinator.pool) { (
            buffers: repeat (UnsafeMutableBufferPointer<(each T).InnerType>, [Entity.ID: Array.Index])
        ) in
            let accessors = (repeat TypedAccess(buffer: (each buffers).0, indices: (each buffers).1))
            for entityId in entityIDs {
                result[entityId] = (repeat (each accessors).access(entityId).value)
            }
        }

        return result
    }

    public func fetchOne(_ coordinator: inout Coordinator) -> (entityID: Entity.ID, components: (repeat (each T).InnerType))? {
        var result: (entityID: Entity.ID, components: (repeat (each T).InnerType))? = nil
        let entityIDs = coordinator.pool.entities(
            repeat (each T).InnerType.self,
            included: backstageComponents,
            excluded: excludedComponents
        )
        withTypedBuffers(&coordinator.pool) { (
            buffers: repeat (UnsafeMutableBufferPointer<(each T).InnerType>, [Entity.ID: Array.Index])
        ) in
            let accessors = (repeat TypedAccess(buffer: (each buffers).0, indices: (each buffers).1))
            for entityId in entityIDs {
                result = (entityID: entityId, (repeat (each accessors).access(entityId).value))
                break
            }
        }

        return result
    }

    // TODO: Make a version which returns the result (Most useful together with entity ID filters).
    //       Call it `fetchAll` and `fetchOne`.
    //       E.g.: let transform = coordinator.fetchOne(Query { Transform.self; Entities(4) })
    public func callAsFunction(_ coordinator: inout Coordinator, _ handler: (repeat (each T).ResolvedType) -> Void) {
        perform(&coordinator, handler)
    }

    public var signature: ComponentSignature {
        var signature = ComponentSignature()

        for tag in backstageComponents {
            signature = signature.appending(tag)
        }

        func add(_ tag: ComponentTag) {
            signature = signature.appending(tag)
        }

        repeat signature = signature.appending((each T).componentTag)

        return signature
    }
}

public struct TypedAccess<C: Component> {
    /*@usableFromInline*/ public var buffer: UnsafeMutableBufferPointer<C>
    /*@usableFromInline*/ public var indices: [Entity.ID: Array.Index]

    @usableFromInline
    init(buffer: UnsafeMutableBufferPointer<C>, indices: [Entity.ID : Array.Index]) {
        self.buffer = buffer
        self.indices = indices
    }

    @inlinable @inline(__always)
    public subscript(_ id: Entity.ID) -> C {
        _read {
            yield buffer[indices[id]!]
        }
        nonmutating _modify {
            yield &buffer[indices[id]!]
        }
    }

    @inlinable @inline(__always)
    public func access(_ id: Entity.ID) -> SingleTypedAccess<C> {
        SingleTypedAccess(buffer: buffer.baseAddress!.advanced(by: indices[id]!))
    }
}

public struct SingleTypedAccess<C: Component> {
    @usableFromInline internal var buffer: UnsafeMutablePointer<C>

    @usableFromInline
    init(buffer: UnsafeMutablePointer<C>) {
        self.buffer = buffer
    }

    @inlinable @inline(__always)
    public var value: C {
        _read {
            yield buffer.pointee
        }
        nonmutating _modify {
            yield &buffer.pointee
        }
    }
}

public protocol ComponentResolving {
    associatedtype ResolvedType = Self
    associatedtype InnerType: Component = Self
    static func makeResolved(access: TypedAccess<InnerType>, entityID: Entity.ID) -> ResolvedType
}

public extension ComponentResolving where Self: Component, ResolvedType == Self, InnerType == Self {
    static func makeResolved(access: TypedAccess<InnerType>, entityID: Entity.ID) -> Self {
        access[entityID]
    }
}

extension Write: ComponentResolving {
    public typealias ResolvedType = Write<Wrapped>
    public typealias InnerType = Wrapped

    public static func makeResolved(access: TypedAccess<Wrapped>, entityID: Entity.ID) -> Write<Wrapped> {
        Write<Wrapped>(access: access.access(entityID))
    }
}

public struct BuiltQuery<each T: Component & ComponentResolving> {
    let composite: Query<repeat each T>
}

@resultBuilder
public enum QueryBuilder {
    public static func buildExpression<C: Component>(_ c: C.Type) -> BuiltQuery<C> {
        BuiltQuery(composite: Query<C>(backstageComponents: [], excludedComponents: []))
    }

    public static func buildExpression<C: Component>(_ c: Write<C>.Type) -> BuiltQuery<Write<C>> {
        BuiltQuery(composite: Query<Write<C>>(backstageComponents: [], excludedComponents: []))
    }

    public static func buildExpression<C: Component>(_ c: With<C>.Type) -> BuiltQuery< > {
        BuiltQuery(composite: Query< >(backstageComponents: [C.componentTag], excludedComponents: []))
    }

    public static func buildExpression<C: Component>(_ c: Without<C>.Type) -> BuiltQuery< > {
        BuiltQuery(composite: Query< >(backstageComponents: [], excludedComponents: [C.componentTag]))
    }

    public static func buildPartialBlock<each T>(first: BuiltQuery<repeat each T>) -> BuiltQuery<repeat each T> {
        first
    }

    public static func buildPartialBlock<each T, each U>(
        accumulated: BuiltQuery<repeat each T>,
        next: BuiltQuery<repeat each U>
    ) -> BuiltQuery<repeat each T, repeat each U> {
        BuiltQuery(
            composite:
                Query<repeat each T,repeat each U>(
                    backstageComponents:
                        accumulated.composite.backstageComponents.union(next.composite.backstageComponents),
                    excludedComponents:
                        accumulated.composite.excludedComponents.union(next.composite.excludedComponents),
                )
        )
    }
}

public extension Query {
    init(@QueryBuilder _ content: () -> BuiltQuery<repeat each T>) {
        let built = content()
        self = built.composite
    }
}

protocol WritableComponent: Component {
    associatedtype Wrapped: Component
}

@dynamicMemberLookup
public struct Write<C: Component>: WritableComponent {
    public static var componentTag: ComponentTag { C.componentTag }

    public typealias Wrapped = C

    let access: SingleTypedAccess<C>

    public subscript<R>(dynamicMember keyPath: WritableKeyPath<C, R>) -> R {
        _read {
            yield access.value[keyPath: keyPath]
        }
        nonmutating _modify {
            yield &access.value[keyPath: keyPath]
        }
    }
}

public struct With<C: Component>: Component {
    public static var componentTag: ComponentTag { C.componentTag }

    public typealias Wrapped = C
}

public struct Without<C: Component>: Component {
    public static var componentTag: ComponentTag { C.componentTag }
}

@discardableResult
@usableFromInline
func withTypedBuffers<each C: Component, R>(
    _ pool: inout ComponentPool,
    _ body: (repeat (UnsafeMutableBufferPointer<each C>, [Entity.ID: Array.Index])) throws -> R
) rethrows -> R? {
    var tuple: (repeat (UnsafeMutableBufferPointer<each C>, [Entity.ID: Array.Index]))? = nil

    func buildTuple() -> (repeat (UnsafeMutableBufferPointer<each C>, [Entity.ID: Array.Index]))? {
        return (repeat tryGetBuffer((each C).self)!)
    }

    func tryGetBuffer<D: Component>(_ type: D.Type) -> (UnsafeMutableBufferPointer<D>, [Entity.ID: Array.Index])? {
        guard let anyArray = pool.components[D.componentTag] else { return nil }
        var result: (UnsafeMutableBufferPointer<D>, [Entity.ID: Array.Index])? = nil
        anyArray.withBuffer(D.self) { buffer, entitiesToIndices in
            result = (buffer, entitiesToIndices)
        }
        return result
    }

    guard let built = buildTuple() else { return nil }
    tuple = built
    return try body(repeat each tuple!)
}
