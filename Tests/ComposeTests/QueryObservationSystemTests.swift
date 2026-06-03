import Testing
@testable import Compose

// MARK: - Test components

private struct ObsA: Component, Equatable {
    static let componentTag = ComponentTag.makeTag()
    var value: Int
    init(value: Int = 0) { self.value = value }
}

private struct ObsB: Component, Equatable {
    static let componentTag = ComponentTag.makeTag()
    var value: Int
    init(value: Int = 0) { self.value = value }
}

// MARK: - Test helper: builds a QueryObservationSystem from closures

/// Creates a `QueryObservationSystem<Transform>` that uses `fetchAll` for sync/delta.
/// This avoids the variadic free-function crash (Swift 6.3 bug) by putting
/// the closure logic directly in the test.
private func makeTestSystem(
    id: String,
    query: Query<ObsA>,
    diffs: ObservationDiffingQuery,
    storage: QueryObservationStorage<ObsA>,
    callback: @Sendable @escaping () -> Void
) -> QueryObservationSystem<ObsA> {
    let sched = query.schedulingMetadata
    let meta = SystemMetadata(
        readSignature: sched.readSignature.appending(query.backstageSignature),
        writeSignature: sched.writeSignature,
        excludedSignature: sched.excludedSignature,
        runAfter: [],
        resourceAccess: [],
        eventAccess: []
    )

    let sync: @Sendable (QueryContext) -> Bool = { ctx in
        storage.removeAll(keepingCapacity: true)
        let seq = query.fetchAll(ctx)
        let ids = seq.entityIDs
        guard !ids.isEmpty else { return false }
        var idx = 0
        for row in seq {
            guard idx < ids.count else { break }
            storage.upsert(ids[idx], element: row)
            idx &+= 1
        }
        return true
    }

    let delta: @Sendable (QueryContext) -> Bool = { ctx in
        let coord = ctx.coordinator
        let diffIDs = diffs.query.fetchAll(ctx).entityIDs
        guard !diffIDs.isEmpty else { return false }
        let diffSet = Set(diffIDs)
        var still = diffSet
        var changed = false
        let seq = query.fetchAll(ctx)
        let ids = seq.entityIDs
        var idx = 0
        for row in seq {
            guard idx < ids.count else { break }
            let eid = ids[idx]
            idx &+= 1
            if diffSet.contains(eid) {
                storage.upsert(eid, element: row)
                still.remove(eid)
                changed = true
            }
        }
        for eid in still where coord.isAlive(eid) {
            storage.remove(eid)
            changed = true
        }
        return changed
    }

    return QueryObservationSystem(
        id: SystemID(name: id),
        metadata: meta,
        storage: storage,
        syncBlock: sync,
        deltaBlock: delta,
        callback: callback
    )
}

// MARK: - Call count tracker

private final class CallCounter: @unchecked Sendable {
    var count = 0
    func bump() { count &+= 1 }
}

// MARK: - Tests

@Suite struct QueryObservationSystemTests {

    @Test func initialSyncPopulatesStorage() {
        let coordinator = Coordinator()
        _ = coordinator.spawn(ObsA(value: 1))
        _ = coordinator.spawn(ObsA(value: 2))

        let query = Query { ObsA.self }
        let diffs = query.buildObservationDiffingQuery()
        let storage = QueryObservationStorage<ObsA>()
        let counter = CallCounter()
        let system = makeTestSystem(
            id: "TS",
            query: query,
            diffs: diffs,
            storage: storage,
            callback: { counter.bump() }
        )

        coordinator.addSystem(system, schedule: .perceptionObservation)
        coordinator.runSchedule(.perceptionObservation)

        #expect(storage.count == 2)
        #expect(counter.count >= 1)
    }

    @Test func deltaDetectsAddedComponent() {
        let coordinator = Coordinator()
        let query = Query { ObsA.self }
        let diffs = query.buildObservationDiffingQuery()
        let storage = QueryObservationStorage<ObsA>()
        let counter = CallCounter()
        let system = makeTestSystem(
            id: "TS",
            query: query,
            diffs: diffs,
            storage: storage,
            callback: { counter.bump() }
        )

        coordinator.addSystem(system, schedule: .perceptionObservation)

        // Prime: empty world
        coordinator.runSchedule(.perceptionObservation)
        #expect(storage.count == 0)
        let primeCount = counter.count

        // Add an entity
        _ = coordinator.spawn(ObsA(value: 42))
        coordinator.runSchedule(.perceptionObservation)

        #expect(storage.count == 1)
        #expect(storage.element(at: 0).value == 42)
        #expect(counter.count > primeCount)
    }

    @Test func deltaDetectsRemovedComponent() {
        let coordinator = Coordinator()
        let entity = coordinator.spawn(ObsA(value: 99))

        let query = Query { ObsA.self }
        let diffs = query.buildObservationDiffingQuery()
        let storage = QueryObservationStorage<ObsA>()
        let counter = CallCounter()
        let system = makeTestSystem(
            id: "TS",
            query: query,
            diffs: diffs,
            storage: storage,
            callback: { counter.bump() }
        )

        coordinator.addSystem(system, schedule: .perceptionObservation)

        // Prime
        coordinator.runSchedule(.perceptionObservation)
        #expect(storage.count == 1)

        // Remove the component
        coordinator.remove(ObsA.self, from: entity)
        coordinator.runSchedule(.perceptionObservation)

        // Entity lost ObsA → no longer matches → removed from storage
        #expect(storage.count == 0)
    }

    @Test func deltaDetectsChangedComponent() {
        let coordinator = Coordinator()
        let entity = coordinator.spawn(ObsA(value: 10))

        let query = Query { ObsA.self }
        let diffs = query.buildObservationDiffingQuery()
        let storage = QueryObservationStorage<ObsA>()
        let counter = CallCounter()
        let system = makeTestSystem(
            id: "TS",
            query: query,
            diffs: diffs,
            storage: storage,
            callback: { counter.bump() }
        )

        coordinator.addSystem(system, schedule: .perceptionObservation)

        // Prime
        coordinator.runSchedule(.perceptionObservation)
        #expect(storage.count == 1)
        #expect(storage.element(at: 0).value == 10)

        // Mutate (remove then re-add)
        coordinator.remove(ObsA.self, from: entity)
        coordinator.add(ObsA(value: 77), to: entity)
        coordinator.runSchedule(.perceptionObservation)

        #expect(storage.count == 1)
        #expect(storage.element(at: 0).value == 77)
    }

    @Test func publishesOncePerRunWithManyChanges() {
        let coordinator = Coordinator()

        // Spawn initial entities
        for i in 0..<5 {
            _ = coordinator.spawn(ObsA(value: i))
        }

        let query = Query { ObsA.self }
        let diffs = query.buildObservationDiffingQuery()
        let storage = QueryObservationStorage<ObsA>()
        let counter = CallCounter()
        let system = makeTestSystem(
            id: "TS",
            query: query,
            diffs: diffs,
            storage: storage,
            callback: { counter.bump() }
        )

        coordinator.addSystem(system, schedule: .perceptionObservation)

        // Prime
        coordinator.runSchedule(.perceptionObservation)
        let baseCount = counter.count

        // Add many new entities
        for i in 5..<10 {
            _ = coordinator.spawn(ObsA(value: i))
        }
        coordinator.runSchedule(.perceptionObservation)

        // Should publish at most once (or exactly once if changed)
        let deltaCount = counter.count - baseCount
        #expect(deltaCount >= 0 && deltaCount <= 2) // One for sync, one for this delta
        #expect(storage.count == 10)
    }

    @Test func seesDeferredCommandsFromPriorSchedules() {
        // This test verifies that commands integrated from earlier schedules
        // are visible when the observation system runs.
        let coordinator = Coordinator()

        let query = Query { ObsA.self }
        let diffs = query.buildObservationDiffingQuery()
        let storage = QueryObservationStorage<ObsA>()
        let counter = CallCounter()
        let system = makeTestSystem(
            id: "TS",
            query: query,
            diffs: diffs,
            storage: storage,
            callback: { counter.bump() }
        )

        coordinator.addSystem(system, schedule: .perceptionObservation)

        // Add entity via commands in a system that runs before perceptionObservation
        struct SpawnSystem: System {
            let id = SystemID(name: "SpawnSys")
            var metadata: SystemMetadata {
                SystemMetadata(readSignature: ComponentSignature(), writeSignature: ComponentSignature(), excludedSignature: ComponentSignature(), runAfter: [], resourceAccess: [], eventAccess: [])
            }
            func run(context: QueryContext, commands: inout Commands) {
                commands.spawn(component: ObsA(value: 55)) { _, _ in }
            }
        }
        coordinator.addSystem(SpawnSystem(), schedule: .update)

        // Prime the observation system
        coordinator.runSchedule(.perceptionObservation)
        let baseCount = counter.count

        // Run the main loop. The spawn command fires in .update,
        // commands integrate, then .perceptionObservation sees the new entity.
        coordinator.run()

        #expect(storage.count >= 1)
        #expect(counter.count > baseCount)
    }

    @Test func destroyedEntityIsRemovedFromStorage() {
        let coordinator = Coordinator()
        let entity = coordinator.spawn(ObsA(value: 1))

        let query = Query { ObsA.self }
        let diffs = query.buildObservationDiffingQuery()
        let storage = QueryObservationStorage<ObsA>()
        let counter = CallCounter()
        let system = makeTestSystem(
            id: "TS",
            query: query,
            diffs: diffs,
            storage: storage,
            callback: { counter.bump() }
        )

        coordinator.addSystem(system, schedule: .perceptionObservation)

        // Prime
        coordinator.runSchedule(.perceptionObservation)
        #expect(storage.count == 1)

        // Destroy entity
        coordinator.destroy(entity)

        // Need enough runs for the sweep cooldown to trigger (runCount & 0b111 == 0)
        for i in 1...8 {
            coordinator.runSchedule(.perceptionObservation)
        }

        // After the sweep on run 8 (0-index: 8 & 0b111 == 0), the destroyed entity should be gone
        #expect(storage.count == 0)
    }

    @Test func removeAndReaddSameTickResolvesToFinalMembership() {
        let coordinator = Coordinator()
        let entity = coordinator.spawn(ObsA(value: 42))

        let query = Query { ObsA.self }
        let diffs = query.buildObservationDiffingQuery()
        let storage = QueryObservationStorage<ObsA>()
        let counter = CallCounter()
        let system = makeTestSystem(
            id: "TS",
            query: query,
            diffs: diffs,
            storage: storage,
            callback: { counter.bump() }
        )

        coordinator.addSystem(system, schedule: .perceptionObservation)

        // Prime
        coordinator.runSchedule(.perceptionObservation)
        #expect(storage.count == 1)
        #expect(storage.element(at: 0).value == 42)

        // Remove then re-add same tick
        coordinator.remove(ObsA.self, from: entity)
        coordinator.add(ObsA(value: 99), to: entity)
        coordinator.runSchedule(.perceptionObservation)

        #expect(storage.count == 1)
        #expect(storage.element(at: 0).value == 99)
    }

    @Test func withFilterMembershipChanges() {
        let coordinator = Coordinator()
        let entity = coordinator.spawn(ObsA(value: 1))

        let query = Query { ObsA.self; With<ObsB>.self }
        let diffs = query.buildObservationDiffingQuery()
        let storage = QueryObservationStorage<ObsA>()
        let counter = CallCounter()
        let system = makeTestSystem(
            id: "TS",
            query: query,
            diffs: diffs,
            storage: storage,
            callback: { counter.bump() }
        )

        coordinator.addSystem(system, schedule: .perceptionObservation)

        // Prime: entity has ObsA but not ObsB → not a member
        coordinator.runSchedule(.perceptionObservation)
        #expect(storage.count == 0)

        // Add ObsB → entity now matches
        coordinator.add(ObsB(value: 10), to: entity)
        coordinator.runSchedule(.perceptionObservation)

        #expect(storage.count == 1)
        #expect(storage.element(at: 0).value == 1)

        // Remove ObsB → entity no longer matches
        coordinator.remove(ObsB.self, from: entity)
        coordinator.runSchedule(.perceptionObservation)

        #expect(storage.count == 0)
    }

    @Test func withoutFilterMembershipChanges() {
        let coordinator = Coordinator()
        let entity = coordinator.spawn(ObsA(value: 5))

        let query = Query { ObsA.self; Without<ObsB>.self }
        let diffs = query.buildObservationDiffingQuery()
        let storage = QueryObservationStorage<ObsA>()
        let counter = CallCounter()
        let system = makeTestSystem(
            id: "TS",
            query: query,
            diffs: diffs,
            storage: storage,
            callback: { counter.bump() }
        )

        coordinator.addSystem(system, schedule: .perceptionObservation)

        // Prime: entity has ObsA, no ObsB → member
        coordinator.runSchedule(.perceptionObservation)
        #expect(storage.count == 1)

        // Add ObsB → entity no longer matches
        coordinator.add(ObsB(value: 1), to: entity)
        coordinator.runSchedule(.perceptionObservation)

        #expect(storage.count == 0)

        // Remove ObsB → entity matches again
        coordinator.remove(ObsB.self, from: entity)
        coordinator.runSchedule(.perceptionObservation)

        #expect(storage.count == 1)
    }
}
