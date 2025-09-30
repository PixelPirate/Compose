import Foundation

public protocol ScheduleLabel: Hashable, SendableMetatype, Sendable {
    static var key: ScheduleLabelKey { get }
}

extension ScheduleLabel {
    public static var key: ScheduleLabelKey {
        ScheduleLabelKey(key: ObjectIdentifier(Self.Type.self))
    }
}

public struct ScheduleLabelKey: Hashable {
    @usableFromInline
    internal let value: ObjectIdentifier

    @usableFromInline
    init(key: ObjectIdentifier) {
        self.value = key
    }

    @inlinable @inline(__always)
    public func hash(into hasher: inout Hasher) {
        hasher.combine(value)
    }

    @inlinable @inline(__always)
    public static func == (lhs: ScheduleLabelKey, rhs: ScheduleLabelKey) -> Bool {
        lhs.value == rhs.value
    }
}

public struct Schedule {
    public let label: ScheduleLabelKey
    private let executor: any Executor
    private var systems: [any System]

    public init<L: ScheduleLabel>(label: L.Type, systems: [any System] = [], executor: any Executor = SingleThreadedExecutor()) {
        self.label = label.key
        self.executor = executor
        self.systems = systems
    }

    public func run(_ coordinator: Coordinator) {
        var commands = Commands()
        executor.run(systems: systems[...], coordinator: coordinator, commands: &commands)
        commands.integrate(into: coordinator)
    }

    public mutating func addSystem(_ system: some System) {
        systems.append(system)
    }
}
