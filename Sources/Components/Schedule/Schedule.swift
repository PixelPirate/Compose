import Foundation
import Atomics

public struct ScheduleLabel: Hashable, Sendable {
    private let rawValue: Int

    public init() {
        self = Self.makeTag()
    }

    private init(rawValue: Int) {
        self.rawValue = rawValue
    }

    nonisolated(unsafe) private static var nextTag: UnsafeAtomic<Int> = .create(0)

    private static func makeTag() -> Self {
        ScheduleLabel(
            rawValue: Self.nextTag.loadThenWrappingIncrement(ordering: .sequentiallyConsistent)
        )
    }
}

public struct Schedule {
    public let label: ScheduleLabel
    public var executor: any Executor
    @usableFromInline
    internal var systems: [any System]

    @inlinable
    public init(label: ScheduleLabel, systems: [any System] = [], executor: any Executor = MultiThreadedExecutor()) {
        self.label = label
        self.executor = executor
        self.systems = systems
    }

    @inlinable
    public func run(_ coordinator: Coordinator) {
        var commands = Commands()
        executor.run(systems: systems[...], coordinator: coordinator, commands: &commands)
        commands.integrate(into: coordinator)
    }

    @inlinable
    public mutating func addSystem(_ system: some System) {
        systems.append(system)
    }
}
