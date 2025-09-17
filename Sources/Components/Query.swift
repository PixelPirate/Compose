//
//  Query.swift
//  Components
//
//  Created by Patrick Horlebein (extern) on 15.09.25.
//

struct Query<each T: Component> where repeat each T: ComponentResolving {
    /// These components will be used for selecting the correct archetype, but they will not be included in the query output.
    let backstageComponents: [ComponentTag] // Or witnessComponents?

    func appending<U>(_ type: U.Type = U.self) -> Query<repeat each T, U> {
        Query<repeat each T, U>(backstageComponents: backstageComponents)
    }

//    extension ComponentArray {
//        subscript(reference entityID: Entity.ID) -> C {
//            _read {
//                let idx = entityToComponents[entityID]!; yield components[idx]
//            }
//            _modify {
//                let idx = entityToComponents[entityID]!; yield &components[idx]
//            }
//        }
//    }
//    query(&pool) { (transform: inout Transform, gravity: Gravity) in
//        transform.position.x += gravity.force.x
//    }

    @inlinable @inline(__always)
    func perform(_ pool: inout ComponentPool, _ handler: (repeat (each T).ResolvedType) -> Void) {
        // TODO: Use the parameter pack to make a big tuple with a typed accessor for each component type.
        //       This accessor should have a `var value { _read _modify }` so it allows to immediatly write to the component.
        @inline(__always)
        func get(_ tag: ComponentTag, _ id: Entity.ID) -> any Component {
            pool[tag, id] // TODO: This is bad, because this does some CoW, casting, etc. on each single component. Instead get all the components beforhand in a typed array
        }
        @inline(__always)
        func set(_ tag: ComponentTag, _ id: Entity.ID, _ newValue: any Component) -> Void {
            pool[tag, id] = newValue
        }
        let entityIDs = pool.entities(repeat (each T).InnerType.self)
        withoutActuallyEscaping(get) { getClosure in
            withoutActuallyEscaping(set) { setClosure in
                let transit = QueryTransit(get: getClosure, set: setClosure)
                for entityID in entityIDs {
                    handler(repeat (each T).makeResolved(transit: transit, entityID: entityID))
                }
            }
        }
    }

    func callAsFunction(_ pool: inout ComponentPool, _ handler: (repeat (each T).ResolvedType) -> Void) {
        perform(&pool, handler)
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

struct QueryTransit { // TODO: This needs to become typed somehow. We can't afford to do `as` casts for each individual component. We need to supply _read and _modify here!
    private let get: (ComponentTag, Entity.ID) -> any Component
    private let set: (ComponentTag, Entity.ID, any Component) -> Void

    init(get: @escaping (ComponentTag, Entity.ID) -> any Component, set: @escaping (ComponentTag, Entity.ID, any Component) -> Void) {
        self.get = get
        self.set = set
    }

    subscript<C: Component>(_ componentType: C.Type = C.self, _ entityID: Entity.ID) -> C {
        `get`(C.componentTag, entityID) as! C
    }

    func modify<C: Component>(_ componentType: C.Type = C.self, _ entityID: Entity.ID, map: (inout C) -> Void) {
        var component = get(C.componentTag, entityID) as! C
        map(&component)
        set(C.componentTag, entityID, component)
    }
}
//struct TypedAccess<C: Component> {
//    @usableFromInline var array: UnsafeMutableBufferPointer<C>
//    @usableFromInline var indexOf: (Entity.ID) -> Int
//}
//struct QueryAccess<each T: Component> {
//    // One typed accessor per pack element
//    let accessors: (repeat TypedAccess<each T>)
//}
//struct TypedTransit<C: Component> {
//    @usableFromInline var array: UnsafeMutableBufferPointer<C>
//    @inlinable func get(_ id: Entity.ID) -> C { array[indexOf(id)] }
//    @inlinable func set(_ id: Entity.ID, _ value: C) { array[indexOf(id)] = value }
//    @usableFromInline var indexOf: (Entity.ID) -> Int
//}

struct TypedAccess<C: Component> {
    @usableFromInline var array: UnsafeMutableBufferPointer<C>
    @usableFromInline var indexOf: (Entity.ID) -> Int

    @inlinable
    subscript(_ id: Entity.ID) -> C {
        _read {
            yield array[indexOf(id)]
        }
        _modify {
            yield &array[indexOf(id)]
        }
    }
}

protocol ComponentResolving {
    associatedtype ResolvedType = Self
    associatedtype InnerType: Component = Self
    static func makeResolved(transit: QueryTransit, entityID: Entity.ID) -> ResolvedType
}

extension ComponentResolving where Self: Component, ResolvedType == Self, InnerType == Self {
    static func makeResolved(transit: QueryTransit, entityID: Entity.ID) -> Self {
        transit[InnerType.self, entityID]
    }
}

extension Write: ComponentResolving {
    typealias ResolvedType = Write<Wrapped>
    typealias InnerType = Wrapped

    static func makeResolved(transit: QueryTransit, entityID: Entity.ID) -> Write<Wrapped> {
        Write<Wrapped> {
            transit[Wrapped.self, entityID]
        } set: { newValue in
            transit.modify(Wrapped.self, entityID) { component in
                component = newValue
            }
        }
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

    // TODO: Give this an TypedAccessor so that we can use _read and _modify here too!
    let get: () -> C
    let set: (C) -> Void

    subscript<R>(dynamicMember keyPath: WritableKeyPath<C, R>) -> R {
        get {
            get()[keyPath: keyPath]
        }
        nonmutating set {
            var value = get()
            value[keyPath: keyPath] = newValue
            set(value)
        }
    }
}
//static func makeResolved(transit: TypedTransit<C>, entityID: Entity.ID) -> Write<C> {
//    let idx = transit.indexOf(entityID)
//    return Write(ptr: transit.array.baseAddress!.advanced(by: idx))
//}
//@dynamicMemberLookup
//struct Write<C: Component> {
//    @usableFromInline var ptr: UnsafeMutablePointer<C>
//
//    @inlinable
//    subscript<R>(dynamicMember keyPath: WritableKeyPath<C, R>) -> R {
//        get { ptr.pointee[keyPath: keyPath] }
//        nonmutating set { ptr.pointee[keyPath: keyPath] = newValue }
//    }
//}

struct With<C: Component>: Component {
    static var componentTag: ComponentTag { C.componentTag }

    typealias Wrapped = C
}

// TODO: Without<C>
