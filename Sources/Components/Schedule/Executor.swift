import Foundation

public protocol Executor {
    func run(systems: ArraySlice<any System>, coordinator: Coordinator, commands: inout Commands)
}

/// This executor will simply loop over all systems and run each synchronously after another in one thread.
/// - Note: This executor will not check for conflicting mutable access.
public struct LinearExecutor: Executor {
    public init() {
    }

    public func run(systems: ArraySlice<any System>, coordinator: Coordinator, commands: inout Commands) {
        let context = QueryContext(coordinator: coordinator)

        for system in systems {
            system.run(context: context, commands: &commands)
        }
    }
}

/// This executor will group all systems into stages where each stage guarantees that there is no conflicting mutable access to the same component or resource between systems.
/// The stages and systems are then run synchronously one after another in the same thread.
public struct SingleThreadedExecutor: Executor {
    public init() {
    }

    public func run(systems: ArraySlice<any System>, coordinator: Coordinator, commands: inout Commands) {
        let context = QueryContext(coordinator: coordinator)
        let stagehand = Stagehand(systems: systems)
        let stages = stagehand.buildStages()

        for stage in stages {
            for system in stage.systems {
                system.run(context: context, commands: &commands)
            }
        }
    }
}

/// This executor will group all systems into stages where each stage guarantees that there is no conflicting mutable access to the same component or resource between systems.
/// The systems in each stage are then run in parallel.
public struct MultiThreadedExecutor: Executor {
    public init() {
    }

    public func run(systems: ArraySlice<any System>, coordinator: Coordinator, commands: inout Commands) {
        let context = QueryContext(coordinator: coordinator)
        let stagehand = Stagehand(systems: systems)
        let stages = stagehand.buildStages()

        for stage in stages {
            let cores = ProcessInfo.processInfo.processorCount
            let chunkSize = (systems.count + cores - 1) / cores

            let send = UnsafeSendable(value: stage.systems)

            DispatchQueue.concurrentPerform(iterations: min(cores, send.value.count)) { i in
                let start = i * chunkSize
                let end = min(start + chunkSize, send.value.count)

                for system in send.value[start..<end] {
                    system.run(context: context, commands: &commands)
                }
            }
        }
    }
}

/// This executor will run each system in parallel.
/// - Attention: This executor will not check for conflicting mutable access.
public struct UnsafeUncheckedMultiThreadedExecutor: Executor {
    public init() {
    }

    public func run(systems: ArraySlice<any System>, coordinator: Coordinator, commands: inout Commands) {
        let context = QueryContext(coordinator: coordinator)

        let cores = ProcessInfo.processInfo.processorCount
        let chunkSize = (systems.count + cores - 1) / cores

        let send = UnsafeSendable(value: systems)

        DispatchQueue.concurrentPerform(iterations: min(cores, send.value.count)) { i in
            let start = i * chunkSize
            let end = min(start + chunkSize, send.value.count)

            for system in send.value[start..<end] {
                system.run(context: context, commands: &commands)
            }
        }
    }
}
