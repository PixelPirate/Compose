import Foundation

struct FixedMainScheduleOrder {
    let labels: [ScheduleLabel]
}


struct FixedMainSystem: System {
    var metadata: SystemMetadata {
        Self.metadata(from: [])
    }

    let id = SystemID(name: "FixedMain")

    func run(context: QueryContext, commands: inout Commands) {
        let order = context.coordinator.resource(FixedMainScheduleOrder.self).labels
        for order in order {
            context.coordinator.runSchedule(order)
        }
    }
}

struct RunFixedMainLoopSystem: System {
    var metadata: SystemMetadata {
        Self.metadata(from: [])
    }

    let id = SystemID(name: "RunFixedMainLoop")

    func run(context: QueryContext, commands: inout Commands) {
        let delta = context.coordinator[resource: WorldClock.self].delta
        context.coordinator[resource: FixedClock.self].accumulate(delta)

        // TODO: Fix this. Endless loop.
        while context.coordinator[resource: FixedClock.self].expend() {
            context.coordinator.runSchedule(.fixedMain)
        }
    }
}
