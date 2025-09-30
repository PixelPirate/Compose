import Atomics

struct MainScheduleOrder {
    let labels: [ScheduleLabelKey]
    let startup: [ScheduleLabelKey]
}

extension MainSystem {
    @usableFromInline
    static func install(into coordinator: Coordinator) {
        coordinator.addRessource(
            MainScheduleOrder(
                labels: [
                    First.key,
                    PreUpdate.key,
                    RunFixedMainLoop.key,
                    Update.key,
                    SpawnScene.key,
                    PostUpdate.key,
                    Last.key
                ],
                startup: [
                    PreStartup.key,
                    Startup.key,
                    PostStartup.key
                ]
            )
        )
        coordinator.addRessource(
            FixedMainScheduleOrder(
                labels: [
                    FixedFirst.key,
                    FixedPreUpdate.key,
                    FixedUpdate.key,
                    FixedPostUpdate.key,
                    FixedLast.key
                ]
            )
        )

        coordinator.addSchedule(Schedule(label: Main.self, executor: SingleThreadedExecutor()))
        coordinator.addSystem(Main.self, system: MainSystem())
        coordinator.addSystem(FixedMain.self, system: FixedMainSystem())
        coordinator.addSystem(RunFixedMainLoop.self, system: RunFixedMainLoopSystem())

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
