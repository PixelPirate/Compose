import Testing
@testable import Compose
import Atomics

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
        diffIDs: [updated, removed, added],
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
        diffIDs: [entity],
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

    let results = QueryObservationResults(storage: storage)
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
