import Testing
@testable import Compose

// MARK: - Test helper: builds a QueryObservationSystem from closures

private func makeTestObsSystem(
    id: String,
    query: Query<StorageTestComponent>,
    diffs: ObservationDiffingQuery,
    storage: QueryObservationStorage<StorageTestComponent>,
    callback: @Sendable @escaping () -> Void
) -> QueryObservationSystem<StorageTestComponent> {
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
            let slot = ids[idx].slot
            let correctedID = Entity.ID(slot: slot, generation: ctx.coordinator.indices[generationFor: slot])
            storage.upsert(correctedID, element: row)
            idx &+= 1
        }
        return true
    }

    let delta: @Sendable (QueryContext) -> Bool = { ctx in
        let coord = ctx.coordinator
        let diffIDs = diffs.query.fetchAll(ctx).entityIDs
        guard !diffIDs.isEmpty else { return false }
        let diffSet = Set(diffIDs.map(\.slot))
        var still = diffSet
        var changed = false
        let seq = query.fetchAll(ctx)
        let ids = seq.entityIDs
        var idx = 0
        for row in seq {
            guard idx < ids.count else { break }
            let slot = ids[idx].slot
            let correctedID = Entity.ID(slot: slot, generation: coord.indices[generationFor: slot])
            idx &+= 1
            if diffSet.contains(slot) {
                storage.upsert(correctedID, element: row)
                still.remove(slot)
                changed = true
            }
        }
        for eid in diffIDs where still.contains(eid.slot) && coord.isAlive(eid) {
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

// MARK: - Helper to advance change tick between runs

/// Runs a schedule, then advances the change tick so subsequent mutations
/// are detectable by the next delta run. Needed when using `runSchedule`
/// directly (rather than the full `coordinator.run()` which advances ticks
/// between schedules).
private func runSchedule(_ coordinator: Coordinator, _ label: ScheduleLabel) {
    coordinator.runSchedule(label)
    coordinator.advanceChangeTick()
}

// MARK: - Tests

@MainActor
@Suite struct QueryObservationSystemTests {
    @Test func initialSyncPopulatesStorage() {
        let coordinator = Coordinator()
        _ = coordinator.spawn(StorageTestComponent(value: 1))
        _ = coordinator.spawn(StorageTestComponent(value: 2))

        let query = Query { StorageTestComponent.self }
        let diffs = query.buildObservationDiffingQuery()
        let storage = QueryObservationStorage<StorageTestComponent>()
        let counter = CallCounter()
        let system = makeTestObsSystem(
            id: "TS",
            query: query,
            diffs: diffs,
            storage: storage,
            callback: { counter.bump() }
        )

        coordinator.addSystem(system, schedule: .perceptionObservation)
        runSchedule(coordinator, .perceptionObservation)

        #expect(storage.count == 2)
        #expect(counter.count >= 1)
    }

    @Test func deltaDetectsAddedComponent() {
        let coordinator = Coordinator()
        let query = Query { StorageTestComponent.self }
        let diffs = query.buildObservationDiffingQuery()
        let storage = QueryObservationStorage<StorageTestComponent>()
        let counter = CallCounter()
        let system = makeTestObsSystem(
            id: "TS",
            query: query,
            diffs: diffs,
            storage: storage,
            callback: { counter.bump() }
        )

        coordinator.addSystem(system, schedule: .perceptionObservation)

        // Prime: empty world
        runSchedule(coordinator, .perceptionObservation)
        #expect(storage.count == 0)
        let primeCount = counter.count

        // Add an entity
        _ = coordinator.spawn(StorageTestComponent(value: 42))
        runSchedule(coordinator, .perceptionObservation)

        #expect(storage.count == 1)
        #expect(storage.element(at: 0).value == 42)
        #expect(counter.count > primeCount)
    }

    @Test func deltaDetectsRemovedComponent() {
        let coordinator = Coordinator()
        let entity = coordinator.spawn(StorageTestComponent(value: 99))

        let query = Query { StorageTestComponent.self }
        let diffs = query.buildObservationDiffingQuery()
        let storage = QueryObservationStorage<StorageTestComponent>()
        let counter = CallCounter()
        let system = makeTestObsSystem(
            id: "TS",
            query: query,
            diffs: diffs,
            storage: storage,
            callback: { counter.bump() }
        )

        coordinator.addSystem(system, schedule: .perceptionObservation)

        // Prime
        runSchedule(coordinator, .perceptionObservation)
        #expect(storage.count == 1)

        // Remove the component
        coordinator.remove(StorageTestComponent.self, from: entity)
        runSchedule(coordinator, .perceptionObservation)

        // Entity lost StorageTestComponent → no longer matches → removed from storage
        #expect(storage.count == 0)
    }

    @Test func deltaDetectsChangedComponent() {
        let coordinator = Coordinator()
        let entity = coordinator.spawn(StorageTestComponent(value: 10))

        let query = Query { StorageTestComponent.self }
        let diffs = query.buildObservationDiffingQuery()
        let storage = QueryObservationStorage<StorageTestComponent>()
        let counter = CallCounter()
        let system = makeTestObsSystem(
            id: "TS",
            query: query,
            diffs: diffs,
            storage: storage,
            callback: { counter.bump() }
        )

        coordinator.addSystem(system, schedule: .perceptionObservation)

        // Prime
        runSchedule(coordinator, .perceptionObservation)
        #expect(storage.count == 1)
        #expect(storage.element(at: 0).value == 10)

        // To change a component, remove and re-add (replace pattern)
        coordinator.remove(StorageTestComponent.self, from: entity)
        coordinator.add(StorageTestComponent(value: 99), to: entity)
        runSchedule(coordinator, .perceptionObservation)

        #expect(storage.count == 1)
        #expect(storage.element(at: 0).value == 99)
        #expect(counter.count >= 2)
    }

    @Test func publishesOncePerRunWithManyChanges() {
        let coordinator = Coordinator()

        // Spawn initial entities
        let entities: [Entity.ID] = (0..<5).map { i in
            coordinator.spawn(StorageTestComponent(value: i))
        }

        let query = Query { StorageTestComponent.self }
        let diffs = query.buildObservationDiffingQuery()
        let storage = QueryObservationStorage<StorageTestComponent>()
        let counter = CallCounter()
        let system = makeTestObsSystem(
            id: "TS",
            query: query,
            diffs: diffs,
            storage: storage,
            callback: { counter.bump() }
        )

        coordinator.addSystem(system, schedule: .perceptionObservation)

        // Prime
        runSchedule(coordinator, .perceptionObservation)
        #expect(storage.count == 5)
        let preCount = counter.count

        // Mutate all entities by removing and re-adding
        for (i, entity) in entities.enumerated() {
            coordinator.remove(StorageTestComponent.self, from: entity)
            coordinator.add(StorageTestComponent(value: i * 10), to: entity)
        }
        runSchedule(coordinator, .perceptionObservation)

        // Only one callback invocation, even with many changes
        #expect(counter.count == preCount + 1)
    }

    @Test func seesDeferredCommandsFromPriorSchedules() {
        // Observation systems on .perceptionObservation must see
        // mutations applied by earlier schedules.
        let coordinator = Coordinator()
        installPerception(into: coordinator)

        let query = Query { StorageTestComponent.self }
        let diffs = query.buildObservationDiffingQuery()
        let storage = QueryObservationStorage<StorageTestComponent>()
        let system = makeTestObsSystem(
            id: "TS",
            query: query,
            diffs: diffs,
            storage: storage,
            callback: {}
        )

        coordinator.addSystem(system, schedule: .perceptionObservation)
        runSchedule(coordinator, .perceptionObservation)
        #expect(storage.count == 0)

        // Spawn entity and run the full main loop (which includes .perceptionObservation)
        _ = coordinator.spawn(StorageTestComponent(value: 88))
        coordinator.run()

        #expect(storage.count == 1)
        #expect(storage.element(at: 0).value == 88)
    }

    @Test func destroyedEntityIsRemovedFromStorage() {
        let coordinator = Coordinator()
        installPerception(into: coordinator)
        let entity = coordinator.spawn(StorageTestComponent(value: 55))

        let query = Query { StorageTestComponent.self }
        let diffs = query.buildObservationDiffingQuery()
        let storage = QueryObservationStorage<StorageTestComponent>()
        let system = makeTestObsSystem(
            id: "TS",
            query: query,
            diffs: diffs,
            storage: storage,
            callback: {}
        )

        coordinator.addSystem(system, schedule: .perceptionObservation)
        runSchedule(coordinator, .perceptionObservation)
        #expect(storage.count == 1)

        coordinator.destroy(entity)
        runSchedule(coordinator, .perceptionObservation)

        // Destroyed entities are evicted during the periodic dead sweep.
        #expect(storage.count == 0)
    }

    @Test func removeAndReaddSameTickResolvesToFinalMembership() {
        let coordinator = Coordinator()
        let entity = coordinator.spawn(StorageTestComponent(value: 10))

        let query = Query { StorageTestComponent.self }
        let diffs = query.buildObservationDiffingQuery()
        let storage = QueryObservationStorage<StorageTestComponent>()
        let system = makeTestObsSystem(
            id: "TS",
            query: query,
            diffs: diffs,
            storage: storage,
            callback: {}
        )

        coordinator.addSystem(system, schedule: .perceptionObservation)

        // Prime
        runSchedule(coordinator, .perceptionObservation)
        #expect(storage.count == 1)
        #expect(storage.element(at: 0).value == 10)

        // Mutate (remove then re-add)
        coordinator.remove(StorageTestComponent.self, from: entity)
        coordinator.add(StorageTestComponent(value: 77), to: entity)
        runSchedule(coordinator, .perceptionObservation)

        #expect(storage.count == 1)
        #expect(storage.element(at: 0).value == 77)
    }

    @Test func withFilterMembershipChanges() {
        let coordinator = Coordinator()
        let entity = coordinator.spawn(
            StorageTestComponent(value: 1),
            StorageTestTag(label: "first")
        )

        // Query requires both
        let query = Query { StorageTestComponent.self; With<StorageTestTag>.self }
        let diffs = query.buildObservationDiffingQuery()
        let storage = QueryObservationStorage<StorageTestComponent>()
        let system = makeTestObsSystem(
            id: "TS",
            query: query,
            diffs: diffs,
            storage: storage,
            callback: {}
        )

        coordinator.addSystem(system, schedule: .perceptionObservation)
        runSchedule(coordinator, .perceptionObservation)
        #expect(storage.count == 1)

        // Remove StorageTestTag — entity no longer matches
        coordinator.remove(StorageTestTag.self, from: entity)
        runSchedule(coordinator, .perceptionObservation)
        #expect(storage.count == 0)

        // Re-add — entity matches again
        coordinator.add(StorageTestTag(label: "second"), to: entity)
        runSchedule(coordinator, .perceptionObservation)
        #expect(storage.count == 1)
    }

    @Test func withoutFilterMembershipChanges() {
        let coordinator = Coordinator()
        _ = coordinator.spawn(
            StorageTestComponent(value: 1),
            StorageTestTag(label: "t")
        )

        // Query excludes StorageTestTag
        let query = Query { StorageTestComponent.self; Without<StorageTestTag>.self }
        let diffs = query.buildObservationDiffingQuery()
        let storage = QueryObservationStorage<StorageTestComponent>()
        let system = makeTestObsSystem(
            id: "TS",
            query: query,
            diffs: diffs,
            storage: storage,
            callback: {}
        )

        coordinator.addSystem(system, schedule: .perceptionObservation)
        runSchedule(coordinator, .perceptionObservation)
        #expect(storage.count == 0)

        // Spawn matching entity
        let entity2 = coordinator.spawn(StorageTestComponent(value: 2))
        runSchedule(coordinator, .perceptionObservation)
        #expect(storage.count == 1)

        // Add excluded component → entity no longer matches
        coordinator.add(StorageTestTag(label: "bad"), to: entity2)
        runSchedule(coordinator, .perceptionObservation)
        #expect(storage.count == 0)
    }
}
