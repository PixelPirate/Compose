import Testing
@testable import Compose
import Atomics
import Foundation

@Test func perceptionObservationRunsAfterLast() async throws {
    let lastRan = ManagedAtomic<Bool>(false)
    let observedAfterLast = ManagedAtomic<Bool>(false)

    struct FlagLastSystem: System {
        let id = SystemID(name: "FlagLastSystem")
        var metadata: SystemMetadata { Self.metadata(from: []) }
        let flag: ManagedAtomic<Bool>

        func run(context: QueryContext, commands: inout Commands) {
            flag.store(true, ordering: .sequentiallyConsistent)
        }
    }

    struct FlagObservationSystem: System {
        let id = SystemID(name: "FlagObservationSystem")
        var metadata: SystemMetadata { Self.metadata(from: []) }
        let lastFlag: ManagedAtomic<Bool>
        let result: ManagedAtomic<Bool>

        func run(context: QueryContext, commands: inout Commands) {
            if lastFlag.load(ordering: .sequentiallyConsistent) {
                result.store(true, ordering: .sequentiallyConsistent)
            }
        }
    }

    let coordinator = Coordinator()
    installPerception(into: coordinator)
    coordinator.addSystem(FlagLastSystem(flag: lastRan), schedule: .last)
    coordinator.addSystem(FlagObservationSystem(lastFlag: lastRan, result: observedAfterLast), schedule: .perceptionObservation)
    coordinator.run()

    let sawIt = observedAfterLast.load(ordering: .sequentiallyConsistent)
    #expect(sawIt)
}

@Test func perceptionObservationSeesIntegratedCommands() async throws {
    let foundEntity = ManagedAtomic<Bool>(false)

    struct SpawnLastSystem: System {
        let id = SystemID(name: "SpawnLastSystem")
        var metadata: SystemMetadata { Self.metadata(from: []) }

        func run(context: QueryContext, commands: inout Commands) {
            commands.spawn { coordinator, entity in
                coordinator.add(Transform(position: .zero, rotation: .zero, scale: .zero), to: entity)
            }
        }
    }

    struct VerifyObservationSystem: System {
        let id = SystemID(name: "VerifyObservationSystem")
        var metadata: SystemMetadata {
            Self.metadata(
                from: [QueryMetadata(
                    readSignature: ComponentSignature(Transform.componentTag),
                    writeSignature: ComponentSignature(),
                    excludedSignature: ComponentSignature()
                )]
            )
        }
        let found: ManagedAtomic<Bool>

        func run(context: QueryContext, commands: inout Commands) {
            let count = Array(Query { Transform.self }.fetchAll(context.coordinator)).count
            if count > 0 {
                found.store(true, ordering: .sequentiallyConsistent)
            }
        }
    }

    let coordinator = Coordinator()
    installPerception(into: coordinator)
    coordinator.addSystem(SpawnLastSystem(), schedule: .last)
    coordinator.addSystem(VerifyObservationSystem(found: foundEntity), schedule: .perceptionObservation)
    coordinator.run()

    let sawIt = foundEntity.load(ordering: .sequentiallyConsistent)
    #expect(sawIt)
}

@Test func customRunPerceptionObservation() async throws {
    let didRun = ManagedAtomic<Bool>(false)

    struct CustomObservationSystem: System {
        let id = SystemID(name: "CustomObservationSystem")
        var metadata: SystemMetadata { Self.metadata(from: []) }
        let flag: ManagedAtomic<Bool>

        func run(context: QueryContext, commands: inout Commands) {
            flag.store(true, ordering: .sequentiallyConsistent)
        }
    }

    let coordinator = Coordinator()
    coordinator.addSystem(CustomObservationSystem(flag: didRun), schedule: .perceptionObservation)
    coordinator.runSchedule(.perceptionObservation)

    let ran = didRun.load(ordering: .sequentiallyConsistent)
    #expect(ran)
}

@Test func perceptionObservationUsesSingleThreadedExecutor() async throws {
    let executionOrder = ManagedAtomic<Int>(0)
    let maxOrder = ManagedAtomic<Int>(0)
    let conflict = ManagedAtomic<Bool>(false)

    struct OrderSystem: System {
        let id: SystemID
        var metadata: SystemMetadata { Self.metadata(from: []) }
        let index: Int
        let current: ManagedAtomic<Int>
        let maxOrder: ManagedAtomic<Int>
        let conflict: ManagedAtomic<Bool>

        func run(context: QueryContext, commands: inout Commands) {
            let seen = current.loadThenWrappingIncrement(ordering: .sequentiallyConsistent)
            if seen != index {
                conflict.store(true, ordering: .sequentiallyConsistent)
            }
            var prev = maxOrder.load(ordering: .sequentiallyConsistent)
            while prev < index {
                let (exchanged, original) = maxOrder.weakCompareExchange(expected: prev, desired: index, ordering: .sequentiallyConsistent)
                if exchanged { break }
                prev = original
            }
        }
    }

    let coordinator = Coordinator()

    for i in 0..<8 {
        coordinator.addSystem(
            OrderSystem(
                id: SystemID(name: "OrderSystem\(i)"),
                index: i,
                current: executionOrder,
                maxOrder: maxOrder,
                conflict: conflict
            ),
            schedule: .perceptionObservation
        )
    }

    coordinator.runSchedule(.perceptionObservation)

    let finalCount = executionOrder.load(ordering: .sequentiallyConsistent)
    let hadConflict = conflict.load(ordering: .sequentiallyConsistent)
    let maxSeen = maxOrder.load(ordering: .sequentiallyConsistent)

    #expect(finalCount == 8)
    #expect(!hadConflict)
    #expect(maxSeen == 7)
}

@Test func emptyPerceptionObservationScheduleRunsWithoutError() {
    let coordinator = Coordinator()
    coordinator.runSchedule(.perceptionObservation)
}

// MARK: - QueryObservationStorage tests

struct StorageTestComponent: Component, Equatable {
    static let componentTag = ComponentTag.makeTag()
    var value: Int
}

struct StorageTestTag: Component, Equatable {
    static let componentTag = ComponentTag.makeTag()
    var label: String
}

@Test func storageStartsEmpty() {
    let storage = QueryObservationStorage<StorageTestComponent>()
    #expect(storage.count == 0)
    #expect(storage.isEmpty)
    #expect(storage.storageVersion == 0)
}

@Test func storageFullResyncPopulates() {
    let storage = QueryObservationStorage<StorageTestComponent>()
    let entities = [
        Entity.ID(slot: 0, generation: 1),
        Entity.ID(slot: 1, generation: 1),
        Entity.ID(slot: 2, generation: 1),
    ]
    storage.fullResync(from: entities.map { ($0, StorageTestComponent(value: $0.slot.rawValue)) })

    #expect(storage.count == 3)
    #expect(!storage.isEmpty)
    #expect(storage.storageVersion > 0)

    for i in 0..<3 {
        #expect(storage.contains(entities[i]))
        #expect(storage.element(at: i).value == entities[i].slot.rawValue)
    }
}

@Test func storagePQDeltaAppliesChangedMembershipOnly() {
    let storage = QueryObservationStorage<StorageTestComponent>()
    let existing = Entity.ID(slot: 0, generation: 1)
    let updated = Entity.ID(slot: 1, generation: 1)
    let removed = Entity.ID(slot: 2, generation: 1)
    let added = Entity.ID(slot: 3, generation: 1)

    storage.fullResync(from: [
        (existing, StorageTestComponent(value: 10)),
        (updated, StorageTestComponent(value: 20)),
        (removed, StorageTestComponent(value: 30)),
    ])

    let rows: [QueryObservationStorage<StorageTestComponent>.Element] = [
        StorageTestComponent(value: 10),
        StorageTestComponent(value: 200),
        StorageTestComponent(value: 400),
    ]
    let changed = storage.pqDelta(
        diffIDs: [updated, removed, added].span,
        ids: [existing, updated, added],
        all: rows
    )

    var valuesByEntity: [Entity.ID: Int] = [:]
    for i in 0 ..< storage.count {
        valuesByEntity[storage.entityID(at: i)] = storage.element(at: i).value
    }

    #expect(changed)
    #expect(storage.count == 3)
    #expect(valuesByEntity[existing] == 10)
    #expect(valuesByEntity[updated] == 200)
    #expect(valuesByEntity[added] == 400)
    #expect(valuesByEntity[removed] == nil)
}

@Test func storagePQDeltaSupportsMultiComponentElements() {
    let storage = QueryObservationStorage<StorageTestComponent, StorageTestTag>()
    let entity = Entity.ID(slot: 0, generation: 1)

    let changed = storage.pqDelta(
        diffIDs: [entity].span,
        ids: [entity],
        all: [(StorageTestComponent(value: 42), StorageTestTag(label: "updated"))]
    )

    let element = storage.element(at: 0)
    #expect(changed)
    #expect(storage.count == 1)
    #expect(element.0.value == 42)
    #expect(element.1.label == "updated")
}

@Test func storageUpsertAddsNewRow() {
    let storage = QueryObservationStorage<StorageTestComponent>()
    let entity = Entity.ID(slot: 0, generation: 1)
    let versionBefore = storage.storageVersion

    storage.upsert(entity, element: StorageTestComponent(value: 42))
    #expect(storage.count == 1)
    #expect(storage.contains(entity))
    #expect(storage.element(at: 0).value == 42)
    #expect(storage.storageVersion > versionBefore)
}

@Test func storageUpsertReplacesExistingRowSameGeneration() {
    let storage = QueryObservationStorage<StorageTestComponent>()
    let entity = Entity.ID(slot: 1, generation: 2)

    storage.upsert(entity, element: StorageTestComponent(value: 10))
    #expect(storage.count == 1)
    #expect(storage.element(at: 0).value == 10)

    let versionBefore = storage.storageVersion
    storage.upsert(entity, element: StorageTestComponent(value: 20))
    #expect(storage.count == 1)
    #expect(storage.element(at: 0).value == 20)
    #expect(storage.storageVersion > versionBefore)
}

@Test func storageUpsertEvictsStaleGeneration() {
    let storage = QueryObservationStorage<StorageTestComponent>()
    let slot = SlotIndex(rawValue: 5)
    let oldEntity = Entity.ID(slot: slot, generation: 1)
    let newEntity = Entity.ID(slot: slot, generation: 2)

    storage.upsert(oldEntity, element: StorageTestComponent(value: 100))
    #expect(storage.count == 1)
    #expect(storage.contains(oldEntity))
    #expect(!storage.contains(newEntity))

    storage.upsert(newEntity, element: StorageTestComponent(value: 200))
    #expect(storage.count == 1)
    #expect(!storage.contains(oldEntity))
    #expect(storage.contains(newEntity))
    #expect(storage.element(at: 0).value == 200)
}

@Test func storageRemoveRemovesOnlyMatchingGeneration() {
    let storage = QueryObservationStorage<StorageTestComponent>()
    let entity1 = Entity.ID(slot: 0, generation: 1)
    let entity2 = Entity.ID(slot: 1, generation: 1)

    storage.upsert(entity1, element: StorageTestComponent(value: 1))
    storage.upsert(entity2, element: StorageTestComponent(value: 2))
    #expect(storage.count == 2)

    // Remove with wrong generation — no effect.
    storage.remove(Entity.ID(slot: 0, generation: 99))
    #expect(storage.count == 2)

    // Remove with correct generation.
    storage.remove(entity1)
    #expect(storage.count == 1)
    #expect(!storage.contains(entity1))
    #expect(storage.contains(entity2))

    // Remove already-removed — no effect.
    storage.remove(entity1)
    #expect(storage.count == 1)
}

@Test func storageRemoveNonExistentIsNoOp() {
    let storage = QueryObservationStorage<StorageTestComponent>()
    let entity = Entity.ID(slot: 99, generation: 1)
    let versionBefore = storage.storageVersion
    storage.remove(entity)
    #expect(storage.count == 0)
    #expect(storage.storageVersion == versionBefore)
}

@Test func storageRemoveAll() {
    let storage = QueryObservationStorage<StorageTestComponent>()
    for i in 0..<5 {
        storage.upsert(Entity.ID(slot: SlotIndex(rawValue: i), generation: 1), element: StorageTestComponent(value: i))
    }
    #expect(storage.count == 5)

    storage.removeAll()
    #expect(storage.count == 0)
    #expect(storage.isEmpty)

    // After removeAll, storage is still usable.
    storage.upsert(Entity.ID(slot: 0, generation: 1), element: StorageTestComponent(value: 99))
    #expect(storage.count == 1)
    #expect(storage.element(at: 0).value == 99)
}

@Test func storageContainsGenerationAware() {
    let storage = QueryObservationStorage<StorageTestComponent>()
    let entity = Entity.ID(slot: 10, generation: 5)

    storage.upsert(entity, element: StorageTestComponent(value: 1))
    #expect(storage.contains(entity))
    #expect(!storage.contains(Entity.ID(slot: 10, generation: 6)))
    #expect(!storage.contains(Entity.ID(slot: 10, generation: 4)))
    #expect(!storage.contains(Entity.ID(slot: 11, generation: 5)))
}

@Test func storageSlotReuseDoesNotCrossContaminate() {
    let storage = QueryObservationStorage<StorageTestComponent>()
    let slot = SlotIndex(rawValue: 3)
    let entityGen1 = Entity.ID(slot: slot, generation: 1)
    let entityGen2 = Entity.ID(slot: slot, generation: 2)

    storage.upsert(entityGen1, element: StorageTestComponent(value: 111))
    #expect(storage.contains(entityGen1))
    #expect(storage.count == 1)

    // Remove gen1 — slot is freed.
    storage.remove(entityGen1)
    #expect(!storage.contains(entityGen1))
    #expect(storage.count == 0)

    // Add gen2 on same slot — must not inherit gen1 data.
    storage.upsert(entityGen2, element: StorageTestComponent(value: 222))
    #expect(storage.count == 1)
    #expect(!storage.contains(entityGen1))
    #expect(storage.contains(entityGen2))
    #expect(storage.element(at: 0).value == 222)
}

@Test func storageMultiComponent() {
    let storage = QueryObservationStorage<StorageTestComponent, StorageTestTag>()
    let entity = Entity.ID(slot: 0, generation: 1)

    storage.upsert(entity, element: (StorageTestComponent(value: 42), StorageTestTag(label: "hello")))
    #expect(storage.count == 1)
    #expect(storage.contains(entity))

    let (comp, tag) = storage.element(at: 0)
    #expect(comp.value == 42)
    #expect(tag.label == "hello")
}

@Test func storageResultsSequence() {
    let storage = QueryObservationStorage<StorageTestComponent>()
    for i in 0..<5 {
        storage.upsert(Entity.ID(slot: SlotIndex(rawValue: i), generation: 1), element: StorageTestComponent(value: i * 10))
    }

    let results: QueryObservationResults<StorageTestComponent> = QueryObservationResults(elements: storage.elements, storageVersion: storage.storageVersion)
    #expect(results.count == 5)
    #expect(!results.isEmpty)

    var values: [Int] = []
    for element in results {
        values.append(element.value)
    }
    #expect(values == [0, 10, 20, 30, 40])
}

@Test func storageVersionIncrementsOnEachMutation() {
    let storage = QueryObservationStorage<StorageTestComponent>()
    let entity = Entity.ID(slot: 0, generation: 1)

    let v0 = storage.storageVersion
    storage.upsert(entity, element: StorageTestComponent(value: 1))
    let v1 = storage.storageVersion
    #expect(v1 > v0)

    storage.upsert(entity, element: StorageTestComponent(value: 2))
    let v2 = storage.storageVersion
    #expect(v2 > v1)

    storage.remove(entity)
    let v3 = storage.storageVersion
    #expect(v3 > v2)

    storage.removeAll()
    let v4 = storage.storageVersion
    #expect(v4 > v3)
}

@Test func storageFullResyncClearsPreviousState() {
    let storage = QueryObservationStorage<StorageTestComponent>()
    storage.upsert(Entity.ID(slot: 0, generation: 1), element: StorageTestComponent(value: 999))
    #expect(storage.count == 1)

    let newEntities = [
        (Entity.ID(slot: 10, generation: 1), StorageTestComponent(value: 10)),
        (Entity.ID(slot: 20, generation: 1), StorageTestComponent(value: 20)),
    ]
    storage.fullResync(from: newEntities)
    #expect(storage.count == 2)
    #expect(!storage.contains(Entity.ID(slot: 0, generation: 1)))
    #expect(storage.contains(Entity.ID(slot: 10, generation: 1)))
    #expect(storage.contains(Entity.ID(slot: 20, generation: 1)))
}

@Test func storageSwapRemovePreservesRemainingOrder() {
    let storage = QueryObservationStorage<StorageTestComponent>()
    for i in 0..<5 {
        storage.upsert(Entity.ID(slot: SlotIndex(rawValue: i), generation: 1), element: StorageTestComponent(value: i))
    }
    #expect(storage.count == 5)

    // Remove middle element (index 2, slot 2).
    storage.remove(Entity.ID(slot: 2, generation: 1))
    #expect(storage.count == 4)

    // Check that remaining elements are intact (gap filled by last).
    var values = Set<Int>()
    for i in 0..<4 {
        values.insert(storage.element(at: i).value)
    }
    #expect(values == Set([0, 1, 3, 4]))
    #expect(!storage.contains(Entity.ID(slot: 2, generation: 1)))
}

// MARK: - Perception integration tests (Ticket 8)

import Perception

@Perceptible
private final class TestBridge: @unchecked Sendable {
    var version: UInt64 = 0
    func bump() { version &+= 1 }
}

private final class InvalidationCounter: @unchecked Sendable {
    var count = 0
    func bump() { count &+= 1 }
}

private func makeBridgedSystem(
    id: String,
    query: Query<StorageTestComponent>,
    diffs: ObservationDiffingQuery,
    storage: QueryObservationStorage<StorageTestComponent>,
    bridge: TestBridge,
    registrar: PerceptionRegistrar
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
        callback: {
            registrar.withMutation(of: bridge, keyPath: \.version) { bridge.bump() }
        }
    )
}

@Suite struct PerceptibleQueryIntegrationTests {

    @Test func trackingFiresOnStorageChange() {
        let coordinator = Coordinator()
        coordinator.spawn(StorageTestComponent(value: 10))

        let query = Query { StorageTestComponent.self }
        let diffs = query.buildObservationDiffingQuery()
        let storage = QueryObservationStorage<StorageTestComponent>()
        let bridge = TestBridge()
        let registrar = PerceptionRegistrar()
        let counter = InvalidationCounter()

        let system = makeBridgedSystem(
            id: "TS", query: query, diffs: diffs,
            storage: storage, bridge: bridge, registrar: registrar
        )
        coordinator.addSystem(system, schedule: .perceptionObservation)
        coordinator.runSchedule(.perceptionObservation) // prime

        withPerceptionTracking {
            _ = bridge.version
        } onChange: {
            counter.bump()
        }

        coordinator.spawn(StorageTestComponent(value: 99))
        coordinator.runSchedule(.perceptionObservation)

        #expect(counter.count == 1)
    }

    @Test func noInvalidationForUnrelatedChange() {
        let coordinator = Coordinator()
        coordinator.spawn(StorageTestComponent(value: 1), StorageTestTag(label: "a"))

        let query = Query { StorageTestComponent.self }
        let diffs = query.buildObservationDiffingQuery()
        let storage = QueryObservationStorage<StorageTestComponent>()
        let bridge = TestBridge()
        let registrar = PerceptionRegistrar()
        let counter = InvalidationCounter()

        let system = makeBridgedSystem(
            id: "TS", query: query, diffs: diffs,
            storage: storage, bridge: bridge, registrar: registrar
        )
        coordinator.addSystem(system, schedule: .perceptionObservation)
        coordinator.runSchedule(.perceptionObservation) // prime

        withPerceptionTracking {
            _ = bridge.version
        } onChange: {
            counter.bump()
        }

        coordinator.runSchedule(.perceptionObservation)

        #expect(counter.count == 0)
    }

    @Test func trackingFiresWhenResultsBecomeEmpty() {
        let coordinator = Coordinator()
        let entity = coordinator.spawn(StorageTestComponent(value: 7))

        let query = Query { StorageTestComponent.self }
        let diffs = query.buildObservationDiffingQuery()
        let storage = QueryObservationStorage<StorageTestComponent>()
        let bridge = TestBridge()
        let registrar = PerceptionRegistrar()
        let counter = InvalidationCounter()

        let system = makeBridgedSystem(
            id: "TS", query: query, diffs: diffs,
            storage: storage, bridge: bridge, registrar: registrar
        )
        coordinator.addSystem(system, schedule: .perceptionObservation)
        coordinator.runSchedule(.perceptionObservation) // prime

        withPerceptionTracking {
            _ = bridge.version
        } onChange: {
            counter.bump()
        }

        coordinator.remove(StorageTestComponent.self, from: entity)
        coordinator.runSchedule(.perceptionObservation)

        #expect(counter.count == 1)
        #expect(storage.isEmpty)
    }

    @Test func singleInvalidationForManyMutations() {
        let coordinator = Coordinator()
        let entities = (0 ..< 10).map { i in
            coordinator.spawn(StorageTestComponent(value: i))
        }

        let query = Query { StorageTestComponent.self }
        let diffs = query.buildObservationDiffingQuery()
        let storage = QueryObservationStorage<StorageTestComponent>()
        let bridge = TestBridge()
        let registrar = PerceptionRegistrar()
        let counter = InvalidationCounter()

        let system = makeBridgedSystem(
            id: "TS", query: query, diffs: diffs,
            storage: storage, bridge: bridge, registrar: registrar
        )
        coordinator.addSystem(system, schedule: .perceptionObservation)
        coordinator.runSchedule(.perceptionObservation) // prime

        withPerceptionTracking {
            _ = bridge.version
        } onChange: {
            counter.bump()
        }

        for (i, entity) in entities.enumerated() {
            coordinator.remove(StorageTestComponent.self, from: entity)
            coordinator.add(StorageTestComponent(value: i * 100), to: entity)
        }
        coordinator.runSchedule(.perceptionObservation)

        #expect(counter.count == 1)
    }
}

// MARK: - Ticket 11: Concurrency and safety tests

@Suite struct PerceptibleQueryConcurrencyTests {

    @MainActor @Test func multiThreadedExecutorDoesNotRaceObservationSystem() async {
        // Register a PerceptibleQuery on the perceptionObservation schedule
        // and run the full main loop (which uses SingleThreadedExecutor for
        // .perceptionObservation). The query should complete without data races.
        let coordinator = Coordinator()
        installPerception(into: coordinator)
        let query = PerceptibleQuery(query: Query { StorageTestComponent.self })

        // Spawn some entities
        for i in 0..<100 {
            _ = coordinator.spawn(StorageTestComponent(value: i))
        }

        // Register the query before the background thread runs
        _ = query.observe(coordinator)

        // Run the coordinator from a background thread while the query is registered
        let iterations = 50
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let thread = Thread {
                for _ in 0..<iterations {
                    coordinator.run()
                }
                continuation.resume()
            }
            thread.start()
        }

        // After concurrent runs, the query should still be usable
        let results = query.observe(coordinator)
        #expect(results.count == 100)
    }

    @MainActor @Test func cancelWhileInactiveIsSafe() {
        let coordinator = Coordinator()
        let query = PerceptibleQuery(query: Query { StorageTestComponent.self })

        // Cancel before any observation — must not crash
        query.cancel()

        // Cancel after observation and coordinator run
        _ = coordinator.spawn(StorageTestComponent(value: 1))
        _ = query.observe(coordinator)
        coordinator.run()
        query.cancel()

        // Cancel again — must be idempotent
        query.cancel()
    }

    @MainActor @Test func cancelAndReobserveWorks() {
        let coordinator = Coordinator()
        installPerception(into: coordinator)
        let query = PerceptibleQuery(query: Query { StorageTestComponent.self })
        _ = coordinator.spawn(StorageTestComponent(value: 42))

        _ = query.observe(coordinator)
        coordinator.run()
        var results = query.observe(coordinator)
        #expect(results.count == 1)

        query.cancel()
        results = query.observe(coordinator)
        // After cancel and re-observe, the system is re-registered and syncs
        coordinator.run()
        results = query.observe(coordinator)
        #expect(results.count == 1)
    }

    @MainActor @Test func coordinatorDeallocationDoesNotCrashOrLeak() {
        var coordinator: Coordinator? = {
            let c = Coordinator()
            installPerception(into: c)
            return c
        }()
        let query = PerceptibleQuery(query: Query { StorageTestComponent.self })
        _ = coordinator!.spawn(StorageTestComponent(value: 1))

        _ = query.observe(coordinator!)
        coordinator!.run()

        // Deallocate the coordinator while the query is still alive
        coordinator = nil

        // The query's weak reference should be nil, and deinit should not crash
        // (calling remove on a nil coordinator is a no-op)
        query.cancel()

        // Re-observe a new coordinator
        let newCoordinator = Coordinator()
        _ = newCoordinator.spawn(StorageTestComponent(value: 99))
        _ = query.observe(newCoordinator)
        newCoordinator.run()
        let results = query.observe(newCoordinator)
        #expect(results.count == 1)
    }

    @MainActor @Test func coordinatorSwitchUnregistersOldSystem() async {
        let coordinator1 = Coordinator()
        installPerception(into: coordinator1)
        let coordinator2 = Coordinator()
        installPerception(into: coordinator2)
        let query = PerceptibleQuery(query: Query { StorageTestComponent.self })

        _ = coordinator1.spawn(StorageTestComponent(value: 1))
        _ = query.observe(coordinator1)
        coordinator1.run()
        #expect(query.observe(coordinator1).count == 1)

        // Switch to coordinator2 — old system should be unregistered
        _ = coordinator2.spawn(StorageTestComponent(value: 2))
        _ = query.observe(coordinator2)
        coordinator2.run()
        #expect(query.observe(coordinator2).count == 1)

        // Run coordinator1 again — the old observation system should not fire
        // (it was unregistered during the switch)
        coordinator1.run()
        // Results should still reflect coordinator2's state
        #expect(query.observe(coordinator2).count == 1)
    }

    @MainActor @Test func observeReturnsIndependentSnapshot() {
        let coordinator = Coordinator()
        installPerception(into: coordinator)
        let query = PerceptibleQuery(query: Query { StorageTestComponent.self })

        _ = coordinator.spawn(StorageTestComponent(value: 10))
        _ = query.observe(coordinator)
        coordinator.run()

        let results1 = query.observe(coordinator)
        #expect(results1.count == 1)

        // Mutate the world
        _ = coordinator.spawn(StorageTestComponent(value: 20))
        coordinator.run()

        // results1 should still reflect the snapshot taken at observe time
        #expect(results1.count == 1)

        // New observe should see the updated world
        let results2 = query.observe(coordinator)
        #expect(results2.count == 2)
    }
}
