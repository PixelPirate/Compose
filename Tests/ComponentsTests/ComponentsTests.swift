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
        for _ in 0...500_000 {
            coordinator.spawn(
                 Gravity(force: Vector3(x: 1, y: 1, z: 1))
            )
        }
        for _ in 0...500_000 {
            coordinator.spawn(
                Transform(position: .zero, rotation: .zero, scale: .zero),
                Gravity(force: Vector3(x: 1, y: 1, z: 1))
            )
        }
        for _ in 0...500_000 {
            coordinator.spawn(
                Transform(position: .zero, rotation: .zero, scale: .zero)
            )
        }
        for _ in 0...500_000 {
            coordinator.spawn(
                Transform(position: .zero, rotation: .zero, scale: .zero),
                Gravity(force: Vector3(x: 1, y: 1, z: 1))
            )
        }
    }
    print("Setup:", setup)

    let duration = clock.measure {
        query.perform(&coordinator) { transform, gravity in
            transform.position.x += gravity.force.x
        }
    }
//~0.012 seconds (Iteration)
//~0.014 seconds (Signature)
    print(duration)
}

@Test func testPerformanceSimple() throws {
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
                Gravity(force: Vector3(x: 0, y: 0, z: 0))
            )
        }
    }
    print("Setup:", setup)

    let duration = clock.measure {
        query.perform(&coordinator) { transform, gravity in
            transform.position.x += gravity.force.x
        }
    }
    // Bevy seems to need 6.7ms for this (Archetypes), 12.5ms with sparse sets
    //~0.011 seconds (Iteration)
    //~0.014 seconds (Signature)
    print(duration)
}

@Test func testManyComponents() {
    struct MockComponent: Component {
        nonisolated(unsafe) static var componentTag: ComponentTag = ComponentTag(rawValue: 0)

        var numberWang: Int = 12
    }

    struct Component_1: Component {
        nonisolated(unsafe) static var componentTag: ComponentTag = ComponentTag(rawValue: 1)

        var numberWang: Int = 12
    }
    struct Component_2: Component {
        nonisolated(unsafe) static var componentTag: ComponentTag = ComponentTag(rawValue: 2)

        var numberWang: Int = 12
    }
    struct Component_3: Component {
        nonisolated(unsafe) static var componentTag: ComponentTag = ComponentTag(rawValue: 3)

        var numberWang: Int = 12
    }
    struct Component_4: Component {
        nonisolated(unsafe) static var componentTag: ComponentTag = ComponentTag(rawValue: 4)

        var numberWang: Int = 12
    }
    struct Component_5: Component {
        nonisolated(unsafe) static var componentTag: ComponentTag = ComponentTag(rawValue: 5)

        var numberWang: Int = 12
    }

    var coordinator = Coordinator()
    let mockComponent = MockComponent()

    for componentNumber in 10..<150 {
        MockComponent.componentTag = ComponentTag(rawValue: componentNumber)
        for _ in 0..<2_000 {
            coordinator.spawn(mockComponent)
        }
        for _ in 0..<2_000 {
            let entity = coordinator.spawn()
            for otherComponentNumber in 10..<componentNumber {
                MockComponent.componentTag = ComponentTag(rawValue: otherComponentNumber)
                coordinator.add(mockComponent, to: entity)
            }
        }
    }
    for _ in 0..<10_000 {
        coordinator.spawn(Component_1())
        coordinator.spawn(Component_2())
        coordinator.spawn(Component_3())
        coordinator.spawn(Component_4())
        coordinator.spawn(Component_5())
        coordinator.spawn(Component_1(), Component_2())
        coordinator.spawn(Component_1(), Component_2(), Component_3())
        coordinator.spawn(Component_1(), Component_2(), Component_3(), Component_4())
        coordinator.spawn(Component_1(), Component_2(), Component_3(), Component_4(), Component_5())
    }

    let query = Query {
        Write<Component_1>.self
        Component_2.self
        Component_3.self
        With<Component_4>.self
        Without<Component_5>.self
    }

    let clock = ContinuousClock()
    let duration = clock.measure {
        query.perform(&coordinator) { com1, com2, com3 in
            com1.numberWang = com2.numberWang * com3.numberWang * com2.numberWang
        }
    }

    //~0.00026 seconds (Iteration)
    //~0.00030 seconds (Signature)
    print(duration)
}

@Test func testRepeat() {
    let clock = ContinuousClock()
    var coordinator = Coordinator()
    for _ in 0..<10_000 {
        coordinator.spawn(
            Transform(position: .zero, rotation: .zero, scale: .zero),
            Gravity(force: .zero)
        )
    }

    let query = Query { Write<Transform>.self; Gravity.self }

    let setup1 = clock.measure {
        for _ in 0..<1000 {
            query.perform(&coordinator) { transform, gravity in
                transform.position.x += gravity.force.x
            }
        }
    }
    print("first run:", setup1)

    let setup2 = clock.measure {
        for _ in 0..<1000 {
            query.perform(&coordinator) { transform, gravity in
                transform.position.x += gravity.force.x
            }
        }
    }
    print("second run (cached):", setup2)

    // (Iteration)
    //first run: 0.112772916 seconds
    //second run (cached): 0.113031667 seconds
    // (Signature)
    //first run: 0.113668375 seconds
    //second run (cached): 0.114894083 seconds
}

@Test func combined() async throws {
    let query = Query {
        WithEntityID.self
        Write<Transform>.self
        With<Gravity>.self
        Without<RigidBody>.self
    }

    var coordinator = Coordinator()

    let expectedID = coordinator.spawn(
        Transform(position: .zero, rotation: .zero, scale: .zero),
        Gravity(force: Vector3(x: 1, y: 1, z: 1))
    )

    for _ in 0..<100 {
        coordinator.spawn(
            Transform(position: .zero, rotation: .zero, scale: .zero)
        )
    }

    for _ in 0..<100 {
        coordinator.spawn(
            Transform(position: .zero, rotation: .zero, scale: .zero),
            Gravity(force: Vector3(x: 1, y: 1, z: 1)),
            RigidBody(velocity: .zero, acceleration: .zero)
        )
    }

    for _ in 0..<100 {
        coordinator.spawn(
            Gravity(force: Vector3(x: 1, y: 1, z: 1))
        )
    }

    for _ in 0..<100 {
        coordinator.spawn(
            RigidBody(velocity: .zero, acceleration: .zero)
        )
    }

    for _ in 0..<100 {
        coordinator.spawn(
            Transform(position: .zero, rotation: .zero, scale: .zero),
            RigidBody(velocity: .zero, acceleration: .zero)
        )
    }

    for _ in 0..<100 {
        coordinator.spawn(
            Gravity(force: Vector3(x: 1, y: 1, z: 1)),
            RigidBody(velocity: .zero, acceleration: .zero)
        )
    }

    #expect(query.fetchOne(&coordinator)?.0 == expectedID)
    #expect(Array(query.fetchAll(&coordinator)).map { $0.0 } == [expectedID])
    await confirmation(expectedCount: 1) { confirmation in
        query.perform(&coordinator) { (_: Entity.ID, _: Write<Transform>) in
            confirmation()
        }
    }
    await confirmation(expectedCount: 1) { confirmation in
        query.performParallel(&coordinator) { (_: Entity.ID, _: Write<Transform>) in
            confirmation()
        }
    }
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

    query.perform(&coordinator) { (transform: Write<Transform>, gravity: Gravity) in
        transform.position.x += gravity.force.x
    }

    let transform = try #require(Query { Transform.self }.fetchOne(&coordinator))
    #expect(transform.position == Vector3(x: 1, y: 0, z: 0))
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

@Test func withoutNotExisting() throws {
    let query = Query {
        Transform.self
        Without<Gravity>.self
    }

    #expect(query.backstageComponents == [])
    #expect(query.excludedComponents == [Gravity.componentTag])
    #expect(query.signature == ComponentSignature(Transform.componentTag))

    var coordinator = Coordinator()

    coordinator.spawn(
        Transform(position: .zero, rotation: .zero, scale: .zero)
    )

    #expect(query.fetchOne(&coordinator) == Transform(position: .zero, rotation: .zero, scale: .zero))
}

@Test func fetchAll() throws {
    var coordinator = Coordinator()

    for _ in 0..<1_000 {
        coordinator.spawn(
            Transform(position: .zero, rotation: .zero, scale: .zero),
            Gravity(force: Vector3(x: 1, y: 1, z: 1))
        )
    }

    let transforms = Query {
        Write<Transform>.self
    }
    .fetchAll(&coordinator)

    #expect(Array(transforms).count == 1_000)

    let multiComponents: LazyQuerySequence<Write<Transform>, Gravity> = Query {
        Write<Transform>.self
        Gravity.self
    }
    .fetchAll(&coordinator)

    #expect(Array(multiComponents).count == 1_000)
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

    let fetchResult = Query {
        WithEntityID.self
        RigidBody.self
    }
    .fetchOne(&coordinator)

    #expect(fetchResult?.0 == expectedEntityID)
    #expect(fetchResult?.1 == RigidBody(velocity: Vector3(x: 1, y: 2, z: 3), acceleration: .zero))
}

@Test func withEntityID() async throws {
    var coordinator = Coordinator()
    let expectedID = coordinator.spawn(Transform(position: .zero, rotation: .zero, scale: .zero))
    coordinator.spawn(RigidBody(velocity: .zero, acceleration: .zero))

    let query = Query {
        WithEntityID.self
        Transform.self
    }

    await confirmation(expectedCount: 1) { confirmation in
        query.perform(&coordinator) { (entityID: Entity.ID, _: Transform) in
            #expect(entityID == expectedID)
            confirmation()
        }
    }
    await confirmation(expectedCount: 1) { confirmation in
        query.performParallel(&coordinator) { (entityID: Entity.ID, _: Transform) in
            #expect(entityID == expectedID)
            confirmation()
        }
    }
    #expect(query.fetchOne(&coordinator)?.0 == expectedID)

    let all = Array(query.fetchAll(&coordinator))
    #expect(all.count == 1)
    #expect(all[0].0 == expectedID)
    #expect(all[0].1 == Transform(position: .zero, rotation: .zero, scale: .zero))
}

@Test
func testReuseSlot() async throws {
    var coordinator = Coordinator()
    let entityA = coordinator.spawn(Gravity(force: .zero))
    coordinator.destroy(entityA)
    let entityB = coordinator.spawn(Gravity(force: .zero))

    // Destroyed slot gets recycled with new generation:
    #expect(entityA.slot == entityB.slot)
    #expect(entityA.generation != entityB.generation)

    // Using the old ID is ignored:
    coordinator.remove(Gravity.self, from: entityA)
    #expect(Query { Gravity.self }.fetchOne(&coordinator) != nil)

    // Using the current ID works:
    coordinator.remove(Gravity.self, from: entityB)
    #expect(Query { Gravity.self }.fetchOne(&coordinator) == nil)
}

//@Test func entityIDs() {
//    var coordinator = Coordinator()
//
//    #expect(coordinator.indices.archetype.isEmpty)
//    #expect(coordinator.indices.freeIDs.isEmpty)
//    #expect(coordinator.indices.generation.isEmpty)
//    #expect(coordinator.indices.nextID.rawValue == 0)
//
//    let id1 = coordinator.spawn()
//    let id2 = coordinator.spawn()
//
//    #expect(id1 != id2)
//    #expect(coordinator.indices.archetype.isEmpty)
//    #expect(coordinator.indices.freeIDs.isEmpty)
//    #expect(coordinator.indices.generation == [1, 1])
//    #expect(coordinator.indices.nextID.rawValue == 2)
//    #expect(id1.generation == 1)
//    #expect(id2.generation == 1)
//
//    coordinator.destroy(id1)
//
//    #expect(coordinator.indices.archetype.isEmpty)
//    #expect(coordinator.indices.freeIDs == [id1.slot])
//    #expect(coordinator.indices.generation == [2, 1])
//    #expect(coordinator.indices.nextID.rawValue == 2)
//
//    let id3 = coordinator.spawn()
//
//    #expect(id3.slot == id1.slot)
//    #expect(id3.generation != id1.generation)
//    #expect(id3.generation == 3)
//    #expect(coordinator.indices.archetype.isEmpty)
//    #expect(coordinator.indices.freeIDs == [])
//    #expect(coordinator.indices.generation == [3, 1])
//    #expect(coordinator.indices.nextID.rawValue == 2)
//}
