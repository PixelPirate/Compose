import Atomics

struct MainScheduleOrder {
    let labels: [ScheduleLabel]
    let startup: [ScheduleLabel]
}

extension MainSystem {
    @usableFromInline
    static func install(into coordinator: Coordinator) {
        coordinator.addRessource(
            MainScheduleOrder(
                labels: [
                    .first,
                    .preUpdate,
                    .runFixedMainLoop,
                    .update,
                    .spawnScene,
                    .postUpdate,
                    .last
                ],
                startup: [
                    .preStartup,
                    .startup,
                    .postStartup
                ]
            )
        )
        coordinator.addRessource(
            FixedMainScheduleOrder(
                labels: [
                    .fixedFirst,
                    .fixedPreUpdate,
                    .fixedUpdate,
                    .fixedPostUpdate,
                    .fixedLast
                ]
            )
        )

        coordinator.addSchedule(Schedule(label: .main, executor: LinearExecutor()))
        coordinator.addSystem(.main, system: MainSystem())
        coordinator.addSystem(.fixedMain, system: FixedMainSystem())
        coordinator.addSystem(.runFixedMainLoop, system: RunFixedMainLoopSystem())

        TimeSystem.install(into: coordinator)
    }
}

struct MainSystem: System {
    private static let first = ManagedAtomic<Bool>(true)

    var metadata: SystemMetadata {
        Self.metadata(from: [])
    }

    let id = SystemID(name: "Main")

    func run(context: QueryContext, commands: inout Commands) {
        if Self.first.exchange(false, ordering: .relaxed) {
            let order = context.coordinator.resource(MainScheduleOrder.self).startup
            for order in order {
                context.coordinator.runSchedule(order)
            }
        }
        let order = context.coordinator.resource(MainScheduleOrder.self).labels
        for order in order {
            context.coordinator.runSchedule(order)
        }
    }
}
