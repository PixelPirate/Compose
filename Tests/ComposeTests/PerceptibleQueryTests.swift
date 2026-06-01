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
