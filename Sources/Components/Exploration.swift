/* In Bevy:
 #[derive(Component)]
 struct Position {
     x: f32,
     y: f32,
 }

 fn print_position_system(query: Query<&Position>) {
     for position in &query {
         println!("position: {} {}", position.x, position.y);
     }
 }

 struct Entity(u64);

 let mut world = World::new();
 let mut schedule = Schedule::default();
 schedule.add_systems((
     system_two,
     system_one.before(system_two),
     system_three.after(system_two),
 ));
 // OR: App::new().add_systems(Update, hello_world).run(); // `Update` is a `Schedule`

 schedule.run(&mut world);

 */

/*
 Other idea: use Tupple and Mirror
 struct Query<X> {}
 Query<(Position, Velocity, Health)>
 If the Mirror stuff happens only one time for each system, the drawback would be neglitable.
 It would also be easy to identify Write<> and With<>
 */

import Foundation

struct Vector3: Hashable {
    var x: Float
    var y: Float
    var z: Float

    static let zero = Vector3(x: 0, y: 0, z: 0)
}

struct Gravity: Component {
    static let componentTag = ComponentTag.makeTag()

    var force: Vector3
}

struct RigidBody: Component {
    static let componentTag = ComponentTag.makeTag()

    var velocity: Vector3
    var acceleration: Vector3
}

struct Transform: Component {
    static let componentTag = ComponentTag.makeTag()

    var position: Vector3
    var rotation: Vector3
    var scale: Vector3
}

struct Person: Component {
    static let componentTag = ComponentTag.makeTag()
}

struct PhysicsSystem: System {
    let id = SystemID(name: "PhysicsSystem")
    var entities: Set<Entity.ID> = []
    let signature = ComponentSignature(Gravity.componentTag, RigidBody.componentTag, Transform.componentTag)

    func update(deltaTime: Float, coordinator: inout Coordinator) {
//        for entityID in entities {
//            let rigidBody = coordinator[RigidBody.self, entityID]
//            let gravity = coordinator[Gravity.self, entityID]
//            coordinator.modify(Transform.self, entityID) { transform in
//                transform.position.x += rigidBody.velocity.x * deltaTime
//            }
//            coordinator.modify(RigidBody.self, entityID) { rigidBody in
//                rigidBody.velocity.x += gravity.force.x * deltaTime
//            }
//        }
    }
}

func test() {
    var coordinator = Coordinator()
    let physicsSystem = PhysicsSystem()
    coordinator.add(physicsSystem)
    coordinator.updateSystemSignature(physicsSystem.signature, systemID: physicsSystem.id)

    let entities = (0..<100).map { Entity(id: Entity.ID(rawValue: $0)) }

    for var entity in entities {
        coordinator.addComponent(
            Gravity(force: Vector3(x: 0, y: 0, z: 0)),
            to: &entity
        )
        coordinator.addComponent(
            RigidBody(
                velocity: Vector3(x: 0, y: 0, z: 0),
                acceleration: Vector3(x: 0, y: 0, z: 0)
            ),
            to: &entity
        )
        coordinator.addComponent(
            Transform(
                position: Vector3(x: 0, y: 0, z: 0),
                rotation: Vector3(x: 0, y: 0, z: 0),
                scale: Vector3(x: 0, y: 0, z: 0)
            ),
            to: &entity
        )
    }

    var deltaTime: Float = 0

    while true {
        let start = Date()
        physicsSystem.update(deltaTime: deltaTime, coordinator: &coordinator)
        let stop = Date()
        deltaTime = Float(stop.timeIntervalSince(start))
    }
}
