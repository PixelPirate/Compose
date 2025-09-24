/* TODO: Flesh out systems.
 fn enemy_detect_player(
     // access data from resources
     mut ai_settings: ResMut<EnemyAiSettings>,
     gamemode: Res<GameModeData>,
     // access data from entities/components
     query_player: Query<&Transform, With<Player>>,
     query_enemies: Query<&mut Transform, (With<Enemy>, Without<Player>)>,
     // in case we want to spawn/despawn entities, etc.
     mut commands: Commands,
 ) {
     // ... implement your behavior here ...
 }
 */

@usableFromInline
struct QuerySignature: Hashable {
    @usableFromInline
    var included: ComponentSignature
    @usableFromInline
    var excluded: ComponentSignature
}

struct Commands {

}

protocol SysTest {
    var querySignature: QuerySignature { get }

    func run(coordinator: inout Coordinator, commands: inout Commands)
}

struct GravitySystem: SysTest {
    var querySignature: QuerySignature {
        QuerySignature(
            included: query.signature,
            excluded: query.excludedSignature
        )
    }

    let query = Query {
        Write<Transform>.self
        Gravity.self
    }

    func run(coordinator: inout Coordinator, commands: inout Commands) {
        query.perform(&coordinator) { transform, gravity in
            transform.position.y -= gravity.force.y
        }
    }
}

struct BigSystem: SysTest {
    nonisolated(unsafe) static let gravityQuery = Query {
        Write<Transform>.self
        Gravity.self
    }

    nonisolated(unsafe) static let floatQuery = Query {
        Write<RigidBody>.self
        Person.self
    }

    let querySignature = QuerySignature(
        included: gravityQuery.signature.appending(floatQuery.signature),
        excluded: gravityQuery.excludedSignature.appending(floatQuery.excludedSignature),
    )

    func run(coordinator: inout Coordinator, commands: inout Commands) {
        Self.gravityQuery.perform(&coordinator) { transform, gravity in
            transform.position.y -= gravity.force.y
        }
        Self.floatQuery.perform(&coordinator) { rigidBody, person in

        }
    }
}

public protocol System {
    var id: SystemID { get }
    var entities: Set<Entity.ID> { get set }
    var signature: ComponentSignature { get }
}

public struct SystemID: Hashable {
    public let rawHashValue: Int

    public init(name: String) {
        rawHashValue = name.hashValue
    }
}

//struct TestSystem: System {
//    let id = SystemID(name: "Test")
//
//    var entities: Set<Entity.ID> = []
//
//    let query = Query {
//        Transform.self
//    }
//
//    var signature: ComponentSignature {
//        query.signature
//    }
//
//    func callAsFunction(_ pool: inout ComponentPool) {
//        query(&pool) { transform in
//
//        }
//    }
//}

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
