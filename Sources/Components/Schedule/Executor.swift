import Foundation

public protocol Executor {
    @inlinable
    func run(systems: ArraySlice<any System>, coordinator: Coordinator, commands: inout Commands)
}

/// This executor will simply loop over all systems and run each synchronously after another in one thread.
public struct SingleThreadedExecutor: Executor {
    public init() {
    }

    @inlinable
    public func run(systems: ArraySlice<any System>, coordinator: Coordinator, commands: inout Commands) {
        let context = QueryContext(coordinator: coordinator)

        for system in systems {
            system.run(context: context, commands: &commands)
        }
    }
}

/// This executor will group all systems into stages where each stage guarantees that there is no conflicting mutable access to the same component or resource between systems.
/// The systems in each stage are then run in parallel.
public struct MultiThreadedExecutor: Executor {
    public init() {
    }

    @inlinable
    public func run(systems: ArraySlice<any System>, coordinator: Coordinator, commands: inout Commands) {
        let context = QueryContext(coordinator: coordinator)
        let stagehand = Stagehand(systems: systems)
        let stages = stagehand.buildStages()

        for stage in stages {
            // `concurrentPerform` recommends that "the number of iterations to be at least three times the number of available cores"
            // but I would presume that the number of systems in a stage would generally not be this high of a number. So instead of
            // the current calculation which tries to keep the iterations low, I should instead always just take the number of systems
            // as the iteration count, but if the number of systems is less then the number of cores, I just run all systems
            // in one thread since the threading overhead is actually quite significant.

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

    @inlinable
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
