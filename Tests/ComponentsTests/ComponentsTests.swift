import Testing
/*@testable*/ import Components

@Test func testPerformance() throws {
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

@Test func write() throws {
    let query = Query {
        Write<Transform>.self
        Gravity.self
    }

    #expect(query.backstageComponents == [])
    #expect(query.excludedComponents == [])
    #expect(query.signature == ComponentSignature(Transform.componentTag, Gravity.componentTag))

    var coordinator = Coordinator()

    coordinator.spawn(
        Transform(position: .zero, rotation: .zero, scale: .zero),
        Gravity(force: Vector3(x: 1, y: 1, z: 1))
    )

    coordinator.perform(query) { (transform: Write<Transform>, gravity: Gravity) in
        transform.position.x += gravity.force.x
    }

    let position = try #require(Query { Transform.self }.fetchOne(&coordinator))
    #expect(position.components.position == Vector3(x: 1, y: 0, z: 0))
}

@Test func with() throws {
    let query = Query {
        Transform.self
        With<Gravity>.self
    }

    #expect(query.backstageComponents == [Gravity.componentTag])
    #expect(query.excludedComponents == [])
    #expect(query.signature == ComponentSignature(Transform.componentTag, Gravity.componentTag))

    var coordinator = Coordinator()

    coordinator.spawn(
        Transform(position: .zero, rotation: .zero, scale: .zero)
    )

    #expect(query.fetchOne(&coordinator) == nil)
}

@Test func without() throws {
    let query = Query {
        Transform.self
        Without<Gravity>.self
    }

    #expect(query.backstageComponents == [])
    #expect(query.excludedComponents == [Gravity.componentTag])
    #expect(query.signature == ComponentSignature(Transform.componentTag))

    var coordinator = Coordinator()

    coordinator.spawn(
        Transform(position: .zero, rotation: .zero, scale: .zero),
        Gravity(force: Vector3(x: 1, y: 1, z: 1))
    )

    #expect(query.fetchOne(&coordinator) == nil)
}

@Test func fetchAll() throws {
    var coordinator = Coordinator()

    for _ in 0..<1_000 {
        coordinator.spawn(
            Transform(position: .zero, rotation: .zero, scale: .zero),
            Gravity(force: Vector3(x: 1, y: 1, z: 1))
        )
    }

    let transforms: [Entity.ID: Transform] = Query {
        Write<Transform>.self
    }
    .fetchAll(&coordinator)

    #expect(transforms.count == 1_000)

    let multiComponents: [Entity.ID: (Transform, Gravity)] = Query {
        Write<Transform>.self
        Gravity.self
    }
    .fetchAll(&coordinator)

    #expect(multiComponents.count == 1_000)
}

@Test func fetchOne() {
    var coordinator = Coordinator()

    for _ in 0..<1_000 {
        coordinator.spawn(
            Transform(position: .zero, rotation: .zero, scale: .zero),
            Gravity(force: Vector3(x: 1, y: 1, z: 1))
        )
    }
    let expectedEntityID = coordinator.spawn(RigidBody(velocity: Vector3(x: 1, y: 2, z: 3), acceleration: .zero))

    let rigidBody = Query {
        RigidBody.self
    }
    .fetchOne(&coordinator)

    #expect(rigidBody?.entityID == expectedEntityID)
    #expect(rigidBody?.components == RigidBody(velocity: Vector3(x: 1, y: 2, z: 3), acceleration: .zero))
}
