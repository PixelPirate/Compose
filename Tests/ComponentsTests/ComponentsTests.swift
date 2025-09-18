import Testing
@testable import Components

@Test
func testComposite() async throws {
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

    var coordinator = Coordinator()
    coordinator.spawn(
        Transform(position: .zero, rotation: .zero, scale: .zero),
        Gravity(force: Vector3(x: 1, y: 1, z: 1)),
        RigidBody(velocity: .zero, acceleration: .zero),
        Person()
    )

    coordinator.perform(query) { transform, gravity in
        transform.position = Vector3(x: gravity.force.x, y: gravity.force.y, z: gravity.force.z)
    }

    await confirmation(expectedCount: 1) { confirmation in
        coordinator.perform(
            Query {
                Transform.self
            }
        ) { transform in
            #expect(transform.position == Vector3(x: 1, y: 1, z: 1))
            confirmation()
        }
    }
}

@Test
func testPerformance() throws {
    let query = Query {
        Write<Transform>.self
        Gravity.self
    }
    let clock = ContinuousClock()

    var coordinator = Coordinator()

    let setup = clock.measure {
        for _ in 0...1_000_000 {
            coordinator.spawn(
                Transform(position: .zero, rotation: .zero, scale: .zero),
                Gravity(force: Vector3(x: 1, y: 1, z: 1))
            )
        }
    }
    print("Setup:", setup)

    let duration = clock.measure {
        coordinator.perform(query) { transform, gravity in
            transform.position.x += gravity.force.x
        }
    }
// Bevy seems to need 6.7ms for this
//~0.6 seconds
    print(duration)
}
