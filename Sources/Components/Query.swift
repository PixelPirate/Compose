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

    @inlinable @inline(__always)
    func perform(_ pool: inout ComponentPool, _ handler: (repeat (each T).ResolvedType) -> Void) {
        @inline(__always)
        func get(_ tag: ComponentTag, _ id: Entity.ID) -> any Component {
            pool[tag, id]
        }
        @inline(__always)
        func set(_ tag: ComponentTag, _ id: Entity.ID, _ newValue: any Component) -> Void {
            pool[tag, id] = newValue
        }
        withoutActuallyEscaping(get) { getClosure in
            withoutActuallyEscaping(set) { setClosure in
                let transit = QueryTransit(get: getClosure, set: setClosure)
                handler(repeat (each T).makeResolved(transit: transit))
            }
        }
    }

//     @inlinable @inline(__always)
//     func perform(_ pool: inout ComponentPool, _ handler: (repeat each T) -> Void) {
//         @inline(__always)
//         func get(_ tag: ComponentTag, _ id: Entity.ID) -> any Component {
//             pool[tag, id]
//         }
//         @inline(__always)
//         func set(_ tag: ComponentTag, _ id: Entity.ID, _ newValue: any Component) -> Void {
//             pool[tag, id] = newValue
//         }
//         withoutActuallyEscaping(get) { getClosure in
//             withoutActuallyEscaping(set) { setClosure in
//                 let transit = QueryTransit(get: getClosure, set: setClosure)
//                 handler(repeat ComponentResolver<each T>.resolve(transit))
//             }
//         }
//     }


//    func callAsFunction(_ pool: inout ComponentPool, _ handler: (repeat each T) -> Void) {
//        perform(&pool, handler)
//    }
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

struct QueryTransit {
    let get: (ComponentTag, Entity.ID) -> any Component
    let set: (ComponentTag, Entity.ID, any Component) -> Void

    subscript<C: Component>(_ componentType: C.Type = C.self, _ entityID: Entity.ID) -> C {
        `get`(C.componentTag, entityID) as! C
    }

    mutating func modify<C: Component>(_ componentType: C.Type = C.self, _ entityID: Entity.ID, map: (inout C) -> Void) {
        var component = get(C.componentTag, entityID) as! C
        map(&component)
        set(C.componentTag, entityID, component)
    }
}

protocol ComponentResolving {
    associatedtype ResolvedType = Self
    static func makeResolved(transit: QueryTransit) -> ResolvedType
}

extension ComponentResolving where Self: Component, ResolvedType == Self {
    static func makeResolved(transit: QueryTransit) -> Self {
        transit.get(Self.componentTag, Entity.ID(rawValue: 0)) as! Self
    }
}

extension Write: ComponentResolving {
    typealias ResolvedType = Write<Wrapped>

    static func makeResolved(transit: QueryTransit) -> Write<Wrapped> {
        Write<Wrapped> {
            transit.get(Wrapped.componentTag, Entity.ID(rawValue: 0)) as! Wrapped
        } set: { newValue in
            transit.set(Wrapped.componentTag, Entity.ID(rawValue: 0), newValue)
        }
    }
}

enum ComponentResolver<T: Component> {
    typealias Output = T

    @inlinable @inline(__always)
    static func resolve(_ transit: QueryTransit) -> T {
        if let writableType = T.self as? any WritableComponent.Type {
            return resolveWritable(writableType, transit: transit) as! T
        } else {
            return transit.get(T.componentTag, Entity.ID(rawValue: 0)) as! T
        }
    }

    @inline(__always)
    private static func resolveWritable<W: WritableComponent, Wrapped>(_: W.Type, transit: QueryTransit) -> any Component where Wrapped == W.Wrapped {
        Write<Wrapped> {
            transit.get(Wrapped.componentTag, Entity.ID(rawValue: 0)) as! Wrapped
        } set: { newValue in
            transit.set(Wrapped.componentTag, Entity.ID(rawValue: 0), newValue)
        }
    }
}

struct TestSystem: System {
    let id = SystemID(name: "Test")

    var entities: Set<Entity.ID> = []

    let query = Query {
        Transform.self
    }

    var signature: ComponentSignature {
        query.signature
    }

    func callAsFunction(_ pool: inout ComponentPool) {
        query(&pool) { transform in

        }
    }
}

/*
@System
struct TestSystem/*: System*/ {
    //let id = SystemID(name: "TestSystem")

    //var entities: Set<Entity.ID> = []

    //let query = CompositeV3 {
    //    Transform.self,
    //    Geometry.self,
    //    Gravity.self
    //}

    //var signature: ComponentSignature {
    //    query.signature
    //}

    //func callAsFunction(_ pool: ComponentPool) {
    //    query.doSomething(pool) { transform, geometry, gravity in
    //        perform(transform: transform, geometry: geometry, gravity)
    //    }
    //}

   func perform(transform: Write<Transform>, geometry: Geometry, _ gravity: With<Gravity>) { // Take all the parameters here to generate the above.
   }
}
 */

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

struct With<C: Component>: Component {
    static var componentTag: ComponentTag { C.componentTag }

    typealias Wrapped = C
}
