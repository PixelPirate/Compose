import Testing
@testable import Components

@Test
func testComposite() throws {
    let query = Query {
        Write<Transform>.self
        Gravity.self
        With<RigidBody>.self
    }

    #expect(
        query.backstageComponents == [
            RigidBody.componentTag
        ]
    )

    #expect(
        query.signature == ComponentSignature(Transform.componentTag, Gravity.componentTag, RigidBody.componentTag)
    )

    var pool = ComponentPool(
        components: [
            Transform.componentTag : ComponentArray(
                (Entity.ID(rawValue: 0), Transform(position: .zero, rotation: .zero, scale: .zero))
            ),
            Gravity.componentTag : ComponentArray(
                (Entity.ID(rawValue: 0), Gravity(force: Vector3(x: 1, y: 1, z: 1)))
            ),
            RigidBody.componentTag : ComponentArray(
                (Entity.ID(rawValue: 0), RigidBody(velocity: .zero, acceleration: .zero))
            ),
            Person.componentTag : ComponentArray(
                (Entity.ID(rawValue: 0), Person())
            ),
        ]
    )

    query(&pool) { transform, gravity in
        transform.position = Vector3(x: gravity.force.x, y: gravity.force.y, z: gravity.force.z)
    }

    let newTransform = pool[Transform.self, Entity.ID(rawValue: 0)]
    #expect(newTransform.position == Vector3(x: 1, y: 1, z: 1))
}

@Test
func testPerformance() throws {
    let query = Query {
        Write<Transform>.self
        Gravity.self
    }
    let clock = ContinuousClock()

    var pool = ComponentPool()
    let setup = clock.measure {
        pool = ComponentPool(
            components: [
                Transform.componentTag : ComponentArray((0...1_000_000).map { (Entity.ID(rawValue: $0), Transform(position: .zero, rotation: .zero, scale: .zero)) }),
                Gravity.componentTag : ComponentArray((0...1_000_000).map { (Entity.ID(rawValue: $0), Gravity(force: Vector3(x: 1, y: 1, z: 1))) }),
            ]
        )
    }
    print("Setup:", setup)

    let duration = clock.measure {
        query(&pool) { transform, gravity in
            transform.position.x += gravity.force.x
        }
    }
//2 seconds
    print(duration)
}
