import Atomics

public struct MainScheduleOrder {
    public var labels: [ScheduleLabel]
    public var startup: [ScheduleLabel]
}

extension MainSystem {
    @usableFromInline
    static func install(into coordinator: Coordinator) {
        coordinator.addResource(
            MainScheduleOrder(
                labels: [
                    .first,
                    .preUpdate,
                    .runFixedMainLoop,
                    .update,
                    .spawnScene,
                    .postUpdate,
                    .last,
                ],
                startup: [
                    .preStartup,
                    .startup,
                    .postStartup
                ]
            )
        )
        coordinator.addResource(
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

        coordinator.addSchedule(Schedule(label: .main, executor: SingleThreadedExecutor()))
        coordinator.addSystem(MainSystem(), schedule: .main)
        coordinator.addSystem(FixedMainSystem(), schedule: .fixedMain)
        coordinator.addSystem(RunFixedMainLoopSystem(), schedule: .runFixedMainLoop)

        TimeSystem.install(into: coordinator)
    }
}

extension ScheduleLabel {
    /// Schedule that runs observation systems after all mutating schedules have completed.
    ///
    /// Observation systems see fully integrated commands from prior schedules.
    /// This schedule runs after `.last` in the default main loop. Custom loops
    /// must run this schedule after all schedules that can mutate observed
    /// components and integrate their deferred commands.
    ///
    /// Uses a `SingleThreadedExecutor` for deterministic execution so that
    /// observation systems update their own storage without racing Perception
    /// publication.
    static let perceptionObservation = ScheduleLabel()
}

public func installPerception(into coordinator: Coordinator) {
    coordinator.addSchedule(Schedule(label: .perceptionObservation, executor: SingleThreadedExecutor()))
    var order = coordinator[resource: MainScheduleOrder.self]
    order.labels.append(.perceptionObservation)
    coordinator[resource: MainScheduleOrder.self] = order
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

    static func reset() {
        _ = Self.first.exchange(true, ordering: .sequentiallyConsistent)
    }
}
