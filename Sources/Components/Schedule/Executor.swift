import Foundation

public protocol Executor {
    @inlinable
    func run(systems: ArraySlice<any System>, coordinator: Coordinator, commands: inout Commands)
}

/// This executor will simply loop over all systems and run each synchronously after another in one thread.
public struct SingleThreadedExecutor: Executor {
    @usableFromInline
    internal let systemCache = FlattenedStageCache()

    public init() {
    }

    @inlinable
    public func run(systems: ArraySlice<any System>, coordinator: Coordinator, commands: inout Commands) {
        let context = QueryContext(coordinator: coordinator)
        let systems = systemCache.cached(systems)

        for system in systems {
            system.run(context: context, commands: &commands)
        }
    }
}

/// This executor will group all systems into stages where each stage guarantees that there is no conflicting mutable access to the same component or resource between systems.
/// The systems in each stage are then run in parallel.
public struct MultiThreadedExecutor: Executor {
    @usableFromInline
    internal let stageCache = StageCache()

    public init() {
    }

    @inlinable
    public func run(systems: ArraySlice<any System>, coordinator: Coordinator, commands: inout Commands) {
        let context = QueryContext(coordinator: coordinator)
        let stages = stageCache.cached(systems)

        // TODO: Low number of systems: Single threaded, medium number: One chunk, large number: Chunks
        for stage in stages {
            // `concurrentPerform` recommends that "the number of iterations to be at least three times the number of available cores"
            // but I would presume that the number of systems in a stage would generally not be this high of a number. So instead of
            // the current calculation which tries to keep the iterations low, I should instead always just take the number of systems
            // as the iteration count, but if the number of systems is less then the number of cores, I just run all systems
            // in one thread since the threading overhead is actually quite significant.

            let cores = ProcessInfo.processInfo.processorCount

            // `chunkSize` represents the best size of a chunk so that all cores are very roughly equally used.
            let chunkSize = (systems.count + cores - 1) / cores

            nonisolated(unsafe) var localCommands = Array(repeating: Commands(), count: systems.count)
            let send = UnsafeSendable(value: stage.systems)

            DispatchQueue.concurrentPerform(iterations: min(cores, send.value.count)) { i in
                let start = i * chunkSize
                let end = min(start + chunkSize, send.value.count)

                for (index, system) in send.value[start..<end].enumerated() {
                    var commands = localCommands[start+i+index]
                    system.run(context: context, commands: &commands)
                    localCommands[start+i+index] = commands
                }
            }

            for local in localCommands {
                commands.append(contentsOf: local)
            }
        }
    }
}

/// This executor will run each system in parallel.
/// - Attention: This executor will not check for conflicting mutable access and will not respect any `runAfter` condition on systems.
public struct UnsafeUncheckedMultiThreadedExecutor: Executor {
    public init() {
    }

    @inlinable
    public func run(systems: ArraySlice<any System>, coordinator: Coordinator, commands: inout Commands) {
        let context = QueryContext(coordinator: coordinator)

        let cores = ProcessInfo.processInfo.processorCount
        let chunkSize = (systems.count + cores - 1) / cores

        nonisolated(unsafe) var localCommands = Array(repeating: Commands(), count: systems.count)
        let send = UnsafeSendable(value: systems)

        DispatchQueue.concurrentPerform(iterations: min(cores, send.value.count)) { i in
            let start = i * chunkSize
            let end = min(start + chunkSize, send.value.count)

            for (index, system) in send.value[start..<end].enumerated() {
                var commands = localCommands[start+i+index]
                system.run(context: context, commands: &commands)
                localCommands[start+i+index] = commands
            }
        }

        for local in localCommands {
            commands.append(contentsOf: local)
        }
    }
}

@usableFromInline
final class StageCache {
    @usableFromInline @inline(__always)
    var cachedStages: [ScheduledStage] = []
    @usableFromInline @inline(__always)
    var cachedSignature: Int? = nil

    @usableFromInline @inline(__always)
    func make(_ systems: ArraySlice<any System>) {
        let hasher = systems.map(\.metadata.id).reduce(into: Hasher()) { partialResult, id in
            partialResult.combine(id)
        }
        let signature = hasher.finalize()
        let stagehand = Stagehand(systems: systems)
        let stages = stagehand.buildStages()
        cachedStages = stages
        cachedSignature = signature
    }

    @usableFromInline @inline(__always)
    func cached(_ systems: ArraySlice<any System>) -> [ScheduledStage] {
        let hasher = systems.map(\.metadata.id).reduce(into: Hasher()) { partialResult, id in
            partialResult.combine(id)
        }
        let signature = hasher.finalize()
        guard signature == cachedSignature else {
            make(systems)
            return cachedStages
        }
        return cachedStages
    }
}

@usableFromInline
final class FlattenedStageCache {
    @usableFromInline @inline(__always)
    var cachedSystems: [any System] = []
    @usableFromInline @inline(__always)
    var cachedSignature: Int? = nil

    @usableFromInline @inline(__always)
    func make(_ systems: ArraySlice<any System>) {
        let stagehand = Stagehand(systems: systems)
        let stages = stagehand.buildStages()
        let line = stages.reduce(into: []) { list, stage in
            list.append(contentsOf: stage.systems)
        }
        let hasher = line.map(\.metadata.id).reduce(into: Hasher()) { partialResult, id in
            partialResult.combine(id)
        }
        let signature = hasher.finalize()

        cachedSystems = line
        cachedSignature = signature
    }

    @usableFromInline @inline(__always)
    func cached(_ systems: ArraySlice<any System>) -> [any System] {
        let hasher = systems.map(\.metadata.id).reduce(into: Hasher()) { partialResult, id in
            partialResult.combine(id)
        }
        let signature = hasher.finalize()
        guard signature == cachedSignature else {
            make(systems)
            return cachedSystems
        }
        return cachedSystems
    }
}
