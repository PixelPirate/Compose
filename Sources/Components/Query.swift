struct Query<each T: Component> where repeat each T: ComponentResolving {
    /// These components will be used for selecting the correct archetype, but they will not be included in the query output.
    let backstageComponents: [ComponentTag] // Or witnessComponents?

    func appending<U>(_ type: U.Type = U.self) -> Query<repeat each T, U> {
        Query<repeat each T, U>(backstageComponents: backstageComponents)
    }

    @inlinable @inline(__always)
    func perform(_ coordinator: inout Coordinator2, _ handler: (repeat (each T).ResolvedType) -> Void) {
        let entityIDs = coordinator.pool.entities(repeat (each T).InnerType.self)
        withTypedBuffers(&coordinator.pool) { (
            buffers: repeat (UnsafeMutableBufferPointer<(each T).InnerType>, [Entity.ID: Array.Index])
        ) in
            let accessors = (repeat TypedAccess(buffer: (each buffers).0, indices: (each buffers).1))
            for entityId in entityIDs {
                handler(repeat (each T).makeResolved(access: each accessors, entityID: entityId))
            }
        }
    }

    func callAsFunction(_ coordinator: inout Coordinator2, _ handler: (repeat (each T).ResolvedType) -> Void) {
        perform(&coordinator, handler)
    }

    var signature: ComponentSignature {
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

struct TypedAccess<C: Component> {
    @usableFromInline var buffer: UnsafeMutableBufferPointer<C>
    @usableFromInline var indices: [Entity.ID: Array.Index]

    @inlinable @inline(__always)
    subscript(_ id: Entity.ID) -> C {
        _read {
            yield buffer[indices[id]!]
        }
        nonmutating _modify {
            yield &buffer[indices[id]!]
        }
    }

    @inlinable @inline(__always)
    func access(_ id: Entity.ID) -> SingleTypedAccess<C> {
        SingleTypedAccess(buffer: buffer.baseAddress!.advanced(by: indices[id]!))
    }
}

struct SingleTypedAccess<C: Component> {
    @usableFromInline var buffer: UnsafeMutablePointer<C>

    @inlinable @inline(__always)
    var value: C {
        _read {
            yield buffer.pointee
        }
        nonmutating _modify {
            yield &buffer.pointee
        }
    }
}

protocol ComponentResolving {
    associatedtype ResolvedType = Self
    associatedtype InnerType: Component = Self
    static func makeResolved(access: TypedAccess<InnerType>, entityID: Entity.ID) -> ResolvedType
}

extension ComponentResolving where Self: Component, ResolvedType == Self, InnerType == Self {
    static func makeResolved(access: TypedAccess<InnerType>, entityID: Entity.ID) -> Self {
        access[entityID]
    }
}

extension Write: ComponentResolving {
    typealias ResolvedType = Write<Wrapped>
    typealias InnerType = Wrapped

    static func makeResolved(access: TypedAccess<Wrapped>, entityID: Entity.ID) -> Write<Wrapped> {
        Write<Wrapped>(access: access.access(entityID))
    }
}

struct BuiltQuery<each T: Component & ComponentResolving> {
    let composite: Query<repeat each T>
}

@resultBuilder
enum QueryBuilder {
    static func buildExpression<C: Component>(_ c: C.Type) -> BuiltQuery<C> {
        BuiltQuery(composite: Query<C>(backstageComponents: []))
    }

    static func buildExpression<C: Component>(_ c: Write<C>.Type) -> BuiltQuery<Write<C>> {
        BuiltQuery(composite: Query<Write<C>>(backstageComponents: []))
    }

    static func buildExpression<C: Component>(_ c: With<C>.Type) -> BuiltQuery< > {
        BuiltQuery(composite: Query< >(backstageComponents: [C.componentTag]))
    }

    static func buildPartialBlock<each T>(first: BuiltQuery<repeat each T>) -> BuiltQuery<repeat each T> {
        first
    }

    static func buildPartialBlock<each T, each U>(
        accumulated: BuiltQuery<repeat each T>,
        next: BuiltQuery<repeat each U>
    ) -> BuiltQuery<repeat each T, repeat each U> {
        BuiltQuery(
            composite: Query<repeat each T,
            repeat each U>(
                backstageComponents: accumulated.composite.backstageComponents + next.composite.backstageComponents
            )
        )
    }
}

extension Query {
    init(@QueryBuilder _ content: () -> BuiltQuery<repeat each T>) {
        let built = content()
        self = built.composite
    }
}

protocol WritableComponent: Component {
    associatedtype Wrapped: Component
}

@dynamicMemberLookup
struct Write<C: Component>: WritableComponent {
    static var componentTag: ComponentTag { C.componentTag }

    typealias Wrapped = C

    let access: SingleTypedAccess<C>

    subscript<R>(dynamicMember keyPath: WritableKeyPath<C, R>) -> R {
        _read {
            yield access.value[keyPath: keyPath]
        }
        nonmutating _modify {
            yield &access.value[keyPath: keyPath]
        }
    }
}

struct With<C: Component>: Component {
    static var componentTag: ComponentTag { C.componentTag }

    typealias Wrapped = C
}

// TODO: Without<C>

@discardableResult
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
