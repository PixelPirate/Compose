import Testing
@testable import Components

@Test func commandsIntegrateAppliesOperations() throws {
    let coordinator = Coordinator()
    let target = coordinator.spawn(Person())

    var spawnedEntity: Entity.ID?
    var runExecuted = false

    var commands = Commands()
    commands.add(component: Transform(position: .zero, rotation: .zero, scale: .zero), to: target)
    commands.remove(component: Person.self, from: target)
    commands.spawn { coordinator, entity in
        spawnedEntity = entity
        coordinator.add(Transform(position: .zero, rotation: .zero, scale: .zero), to: entity)
        coordinator.add(Gravity(force: Vector3(x: 3, y: 0, z: 0)), to: entity)
    }
    commands.destroy(target)
    commands.run { _ in runExecuted = true }

    commands.integrate(into: coordinator)

    #expect(runExecuted)
    #expect(!coordinator.isAlive(target))

    let created = try #require(spawnedEntity)
    #expect(coordinator.isAlive(created))
    #expect(created != target)

    let results = Array(Query { WithEntityID.self; Transform.self; Gravity.self }.fetchAll(coordinator))
    #expect(results.count == 1)
    let (entityID, transform, gravity) = try #require(results.first)
    #expect(entityID == created)
    #expect(transform.position == Vector3.zero)
    #expect(gravity.force == Vector3(x: 3, y: 0, z: 0))
    #expect(Array(Query { Person.self }.fetchAll(coordinator)).isEmpty)
}

@Test func commandsIgnoreStaleEntityIDs() throws {
    let coordinator = Coordinator()
    let stale = coordinator.spawn(Transform(position: .zero, rotation: .zero, scale: .zero))
    coordinator.destroy(stale)
    let replacement = coordinator.spawn(Transform(position: Vector3(x: 1, y: 0, z: 0), rotation: .zero, scale: .zero))

    var commands = Commands()
    commands.remove(component: Transform.self, from: stale)
    commands.destroy(stale)

    commands.integrate(into: coordinator)

    #expect(coordinator.isAlive(replacement))

    let transforms = Array(Query { WithEntityID.self; Transform.self }.fetchAll(coordinator))
    #expect(transforms.count == 1)
    let (entityID, transform) = try #require(transforms.first)
    #expect(entityID == replacement)
    #expect(transform.position == Vector3(x: 1, y: 0, z: 0))
}

@Test func commandsDestroyDuringQueryDoesNotCorruptStorage() throws {
    let coordinator = Coordinator()
    var originalIDs: [Entity.ID] = []
    for i in 0..<32 {
        let id = coordinator.spawn(
            Transform(
                position: Vector3(x: Float(i), y: 0, z: 0),
                rotation: .zero,
                scale: .zero
            )
        )
        originalIDs.append(id)
    }

    let query = Query {
        WithEntityID.self
        Write<Transform>.self
    }

    var commands = Commands()
    var visited = Set<Entity.ID>()

    query(coordinator) { (entity: Entity.ID, transform: Write<Transform>) in
        transform.position.x += 10
        visited.insert(entity)
        commands.destroy(entity)
    }

    #expect(visited == Set(originalIDs))

    commands.integrate(into: coordinator)

    for id in originalIDs {
        #expect(!coordinator.isAlive(id))
    }

    #expect(Array(Query { Transform.self }.fetchAll(coordinator)).isEmpty)

    let newID = coordinator.spawn(Transform(position: .zero, rotation: .zero, scale: .zero))
    #expect(coordinator.isAlive(newID))
    let fetched = try #require(Query { Transform.self }.fetchOne(coordinator))
    #expect(fetched.position == Vector3.zero)
}
