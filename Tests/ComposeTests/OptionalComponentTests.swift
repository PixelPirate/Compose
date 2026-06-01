import Testing
@testable import Components

@Test func optionalQueryHandlesEmptyWorld() {
    let coordinator = Coordinator()
    let query = Query {
        Optional<Transform>.self
    }

    var callCount = 0
    query(coordinator) { (_: Transform?) in
        callCount += 1
    }

    #expect(callCount == 0)

    let results = Array(query(fetchAll: coordinator))
    #expect(results.isEmpty)
}

@Test func optionalComponentsResolvePerEntityPresence() {
    let coordinator = Coordinator()
    let withTransform = coordinator.spawn(
        Transform(position: .zero, rotation: .zero, scale: .zero)
    )
    let withoutTransform = coordinator.spawn(Person())

    let query = Query {
        WithEntityID.self
        Optional<Transform>.self
    }

    var seen: [Entity.ID: Bool] = [:]
    query(coordinator) { (entity: Entity.ID, transform: Transform?) in
        seen[entity] = transform != nil
    }

    #expect(seen[withTransform] == true)
    #expect(seen[withoutTransform] == false)
}

@Test func optionalWriteAllowsUpdatingExistingComponents() throws {
    let coordinator = Coordinator()
    let entityWithTransform = coordinator.spawn(
        Transform(position: .zero, rotation: .zero, scale: .zero)
    )
    _ = coordinator.spawn(Person())

    let query = Query {
        WithEntityID.self
        OptionalWrite<Transform>.self
    }

    query(coordinator) { (entity: Entity.ID, transform: OptionalWrite<Transform>) in
        if entity == entityWithTransform {
            #expect(transform.wrapped != nil)
            if var updated = transform.wrapped {
                updated.position.x += 5
                transform.wrapped = updated
            }
        } else {
            #expect(transform.wrapped == nil)
        }
    }

    let updatedTransform = try #require(Query {
        Transform.self
    }.fetchOne(coordinator))
    #expect(updatedTransform.position.x == 5)
}
