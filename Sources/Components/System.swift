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
    var metadata: SystemMetadata { get }

    func run(coordinator: inout Coordinator, commands: inout Commands)
}

struct MySystem: System {
    let id = SystemID(name: "MySystem")

    var metadata: SystemMetadata {
        Self.metadata(from: [query.metadata, other.metadata])
    }

    let query = Query {
        Transform.self
        Gravity.self
    }

    let other = Query {
        WithEntityID.self
        Person.self
    }

    func run(coordinator: inout Coordinator, commands: inout Commands) {
        _ = query.fetchAll(&coordinator)
        _ = other.fetchAll(&coordinator)
    }
}

public struct QueryMetadata {
    public let signature: ComponentSignature
    public let excludedSignature: ComponentSignature
}

extension Query {
    public var metadata: QueryMetadata {
        QueryMetadata(
            signature: signature,
            excludedSignature: excludedSignature
        )
    }
}

extension System {
    static func metadata(from queries: [QueryMetadata]) -> SystemMetadata {
        var include = ComponentSignature()
        var exclude = ComponentSignature()

        for q in queries {
            include = include.appending(q.signature)
            exclude = exclude.appending(q.excludedSignature)
        }

        return SystemMetadata(
            includedSignature: include,
            excludedSignature: exclude
        )
    }
}

public struct Commands: ~Copyable {
    public struct Command {
        @usableFromInline
        let action: (inout Coordinator) -> Void

        @inlinable @inline(__always)
        public init(action: @escaping (inout Coordinator) -> Void) {
            self.action = action
        }

        @usableFromInline
        func callAsFunction(_ coordinator: inout Coordinator) {
            action(&coordinator)
        }
    }

    @usableFromInline
    internal var queue: [Command] = []

    @inlinable @inline(__always)
    public init(queue: [Command] = []) {
        self.queue = queue
    }

    @inlinable @inline(__always)
    public mutating func add<C: Component>(component: C, to entityID: Entity.ID) {
        queue.append(Command(action: { coordinator in
            coordinator.add(component, to: entityID)
        }))
    }

    @inlinable @inline(__always)
    public mutating func remove<C: Component>(component: C.Type, from entityID: Entity.ID) {
        queue.append(Command(action: { coordinator in
            coordinator.remove(C.componentTag, from: entityID)
        }))
    }

    @inlinable @inline(__always)
    public mutating func spawn<each C: Component>(component: repeat each C, then: @escaping (inout Coordinator, Entity.ID) -> Void) {
        queue.append(Command(action: { coordinator in
            let entityID = coordinator.spawn(repeat each component)
            then(&coordinator, entityID)
        }))
    }

    @inlinable @inline(__always)
    public mutating func spawn(then: @escaping (inout Coordinator, Entity.ID) -> Void) {
        queue.append(Command(action: { coordinator in
            let entityID = coordinator.spawn()
            then(&coordinator, entityID)
        }))
    }

    @inlinable @inline(__always)
    public mutating func destroy(_ entity: Entity.ID) {
        queue.append(Command(action: { coordinator in
            coordinator.destroy(entity)
        }))
    }

    @inlinable @inline(__always)
    public mutating func run(_ action: @escaping (inout Coordinator) -> Void) {
        queue.append(Command(action: { coordinator in
            action(&coordinator)
        }))
    }

    @inlinable @inline(__always)
    mutating func integrate(into coordinator: inout Coordinator) {
        while let command = queue.popLast() {
            command(&coordinator)
        }
    }
}

public struct SystemMetadata {
    public let includedSignature: ComponentSignature
    public let excludedSignature: ComponentSignature
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
