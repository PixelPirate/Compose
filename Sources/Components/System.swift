//
//  System.swift
//  Components
//
//  Created by Patrick Horlebein (extern) on 16.09.25.
//


protocol System {
    var id: SystemID { get }
    var entities: Set<Entity.ID> { get set }
    var signature: ComponentSignature { get }
}

struct SystemID: Hashable {
    let rawHashValue: Int

    init(name: String) {
        rawHashValue = name.hashValue
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
