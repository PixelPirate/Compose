import Testing
@testable import Compose

// MARK: - Test components

private struct EntityQueryTestComponent: Component {
    static let componentTag = ComponentTag.makeTag()
    var value: Int
    init(value: Int = 0) { self.value = value }
}

// MARK: - includesEntityID

@Test func includesEntityIDIsTrueWhenQueryHasWithEntityID() {
    let query = Query { WithEntityID.self; Transform.self }
    #expect(query.isQueryingForEntityID)
}

@Test func includesEntityIDIsFalseWhenQueryDoesNotHaveWithEntityID() {
    let query = Query { Transform.self; Gravity.self }
    #expect(!query.isQueryingForEntityID)
}

@Test func includesEntityIDIsTrueForOnlyWithEntityID() {
    let query = Query { WithEntityID.self }
    #expect(query.isQueryingForEntityID)
}

// MARK: - entityAwareQuery

@Test func entityAwareQueryReturnsCorrectNumberOfElements() {
    let query = Query { Transform.self; Gravity.self }
    let aware = query.withGeneration()
    let coordinator = Coordinator()
    _ = coordinator.spawn(
        Transform(position: .zero, rotation: .zero, scale: .zero),
        Gravity(force: Vector3(x: 1, y: 0, z: 0))
    )
    // FetchAll on the aware query yields 1:1 elements with entity IDs
    let results = Array(aware.fetchAll(coordinator))
    // Element type is (Transform, Gravity, Entity.ID)
    #expect(results.count == 1)
}

@Test func entityAwareQueryGenerationIDsAreCorrect() {
    let coordinator = Coordinator()
    let e1 = coordinator.spawn(
        Transform(position: .zero, rotation: .zero, scale: .zero)
    )
    // Destroy and spawn again — reuse slot with higher generation
    coordinator.destroy(e1)
    let e2 = coordinator.spawn(
        Transform(position: .zero, rotation: .zero, scale: .zero)
    )

    let query = Query { Transform.self }.withGeneration()
    let ids = query.fetchAll(coordinator).entityIDs
    #expect(ids.count == 1)
    #expect(ids[0].generation > 0)
    #expect(ids[0] == e2)
}

// MARK: - matchingEntityIDs

@Test func matchingEntityIDsReturnsAllMatchingEntities() {
    let coordinator = Coordinator()
    let e1 = coordinator.spawn(
        Transform(position: .zero, rotation: .zero, scale: .zero),
        Gravity(force: .zero)
    )
    let e2 = coordinator.spawn(
        Transform(position: Vector3(x: 1, y: 0, z: 0), rotation: .zero, scale: .zero),
        Gravity(force: .zero)
    )
    _ = coordinator.spawn(Gravity(force: .zero)) // no Transform

    let query = Query { Transform.self; Gravity.self }.withGeneration()
    let ids = query.fetchAll(coordinator).entityIDs
    print(e1, e2, ids)
    #expect(ids.count == 2)
    #expect(ids.contains(e1))
    #expect(ids.contains(e2))
}

@Test func matchingEntityIDsReturnsEmptyWhenNoMatch() {
    let coordinator = Coordinator()
    _ = coordinator.spawn(EntityQueryTestComponent(value: 1))
    #expect(Query { Transform.self }.fetchAll(coordinator).entityIDs.isEmpty)
}

@Test func matchingEntityIDsRespectsWithFilter() {
    let coordinator = Coordinator()
    let e1 = coordinator.spawn(
        Transform(position: .zero, rotation: .zero, scale: .zero),
        Gravity(force: .zero)
    )
    _ = coordinator.spawn(Transform(position: .zero, rotation: .zero, scale: .zero))

    let query = Query { Transform.self; With<Gravity>.self }.withGeneration()
    let ids = query.fetchAll(coordinator).entityIDs
    #expect(ids.count == 1)
    #expect(ids[0] == e1)
}

@Test func matchingEntityIDsRespectsWithoutFilter() {
    let coordinator = Coordinator()
    let e1 = coordinator.spawn(
        Transform(position: .zero, rotation: .zero, scale: .zero)
    )
    _ = coordinator.spawn(
        Transform(position: .zero, rotation: .zero, scale: .zero),
        Gravity(force: .zero)
    )

    let query = Query { Transform.self; Without<Gravity>.self }.withGeneration()
    let ids = query.fetchAll(coordinator).entityIDs
    #expect(ids.count == 1)
    #expect(ids[0] == e1)
}

// MARK: - Data consistency: matching + results agree

@Test func matchingEntityIDsAgreeWithFetchAll() {
    let coordinator = Coordinator()
    coordinator.spawn(
        Transform(position: .zero, rotation: .zero, scale: .zero),
        Gravity(force: Vector3(x: 1, y: 0, z: 0))
    )
    coordinator.spawn(
        Transform(position: Vector3(x: 2, y: 0, z: 0), rotation: .zero, scale: .zero),
        Gravity(force: Vector3(x: 3, y: 0, z: 0))
    )

    let query = Query { WithEntityID.self; Transform.self; Gravity.self }
    let fetchAllResults = Array(query.fetchAll(coordinator))
    let ids = query.fetchAll(coordinator).entityIDs

    #expect(ids.count == fetchAllResults.count)
    for (id, (entityID, _, _)) in zip(ids, fetchAllResults) {
        #expect(id == entityID)
    }
}

// MARK: - Optional-only queries

@Test func optionalOnlyQueryReturnsNoSlots() {
    let coordinator = Coordinator()
    let e1 = coordinator.spawn(
        Transform(position: .zero, rotation: .zero, scale: .zero)
    )

    let query = Query { Optional<Transform>.self }
    let ids = query.fetchAll(coordinator).entityIDs
    #expect(ids.count == 0)
}

@Test func optionalOnlyQueryReturnsLiveSlots() {
    let coordinator = Coordinator()
    let e1 = coordinator.spawn(
        Transform(position: .zero, rotation: .zero, scale: .zero)
    )

    let query = Query { WithEntityID.self; Optional<Transform>.self }
    let ids = query.fetchAll(coordinator).entityIDs
    #expect(ids.count == 1)
    #expect(ids[0] == e1)
}

// MARK: - Edge case: empty world

@Test func matchingEntityIDsFromEmptyWorldIsEmpty() {
    let coordinator = Coordinator()
    #expect(Query { Transform.self }.fetchAll(coordinator).entityIDs.isEmpty)
}

// MARK: - Edge case: query with only WithEntityID

@Test func matchingEntityIDsOnOnlyWithEntityIDQuery() {
    let coordinator = Coordinator()
    let e1 = coordinator.spawn(
        Transform(position: .zero, rotation: .zero, scale: .zero)
    )
    let e2 = coordinator.spawn(
        Gravity(force: .zero)
    )

    // WithEntityID only — unconstrained, returns all live slots
    let query = Query { WithEntityID.self }
    let ids = query.fetchAll(coordinator).entityIDs
    #expect(ids.count == 2)
    #expect(ids.contains(e1))
    #expect(ids.contains(e2))
}

// MARK: - includesEntityID after append

@Test func includesEntityIDIsTrueAfterEntityAwareQuery() {
    let query = Query { Transform.self }
    let aware = query.withGeneration()
    #expect(aware.isQueryingForEntityID)
}

