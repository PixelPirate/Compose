//
//  SystemManager.swift
//  Components
//
//  Created by Patrick Horlebein (extern) on 12.09.25.
//

@usableFromInline
struct SystemManager {
    @usableFromInline
    internal var systems: [SystemID: any System] = [:]

    @usableFromInline
    internal var metadata: [SystemID: SystemMetadata] = [:]

    @inlinable @inline(__always)
    mutating func add(_ system: some System) {
        guard !systems.keys.contains(system.id) else {
            fatalError("System already registered.")
        }
        systems[system.id] = system
        metadata[system.id] = system.metadata
    }

    @inlinable @inline(__always)
    mutating func setSignature(_ metadata: SystemMetadata, systemID: SystemID) {
        guard systems.keys.contains(systemID) else {
            fatalError("System not registered.")
        }
        self.metadata[systemID] = metadata
    }

    @inlinable @inline(__always)
    mutating func remove(_ systemID: SystemID) {
        systems.removeValue(forKey: systemID)
        metadata.removeValue(forKey: systemID)
    }
}

/*
 //------------------------------------------------------------
 // App + World
 struct App {
     subApps: [Label: SubApp]
 }
 struct SubApp {
     update_schedule: Label   // by default = Main
 }
 struct World {
     schedules: [Label: Schedule]
     resources: [Type: Resource]
 }

 //------------------------------------------------------------
 // Schedules created on init
 world.addSchedule(Schedule(Main, SingleThreaded))
 world.addSchedule(Schedule(FixedMain, SingleThreaded))
 world.addSchedule(Schedule(RunFixedMainLoop, SingleThreaded))

 // Order resources define the inner buckets
 world.addResource(MainScheduleOrder([First, PreUpdate, RunFixedMainLoop, Update, SpawnScene, PostUpdate, Last],
                                     startup: [PreStartup, Startup, PostStartup]))
 world.addResource(FixedMainScheduleOrder([FixedFirst, FixedPreUpdate, FixedUpdate, FixedPostUpdate, FixedLast]))

 // Primary systems of each schedule
 world.addSystem(Main, Main::run_main)
 world.addSystem(FixedMain, FixedMain::run_fixed_main)
 world.addSystem(RunFixedMainLoop, run_fixed_main_schedule)

 //------------------------------------------------------------
 // Execution flow

 func App.update() {
     let subApp = subApps.main
     world.runSchedule(subApp.update_schedule) // = Main
 }

 // Main schedule
 struct Main {
     func run_main(world) {
         for label in world.resource<MainScheduleOrder>().startup_labels.first_time_only {
             world.runSchedule(label) // PreStartup, Startup, PostStartup (once)
         }
         for label in world.resource<MainScheduleOrder>().labels {
             world.runSchedule(label) // First → PreUpdate → RunFixedMainLoop → Update → SpawnScene → PostUpdate → Last
         }
     }
 }

 // RunFixedMainLoop schedule (time accumulator)
 func run_fixed_main_schedule(world) {
     delta = world.resource<Time<Virtual>>().delta
     world.resource_mut<Time<Fixed>>().accumulate(delta)

     while world.resource_mut<Time<Fixed>>().expend() {
         world.resource_mut<Time>() = world.resource<Time<Fixed>>().as_generic()
         world.runSchedule(FixedMain)  // run inner fixed buckets
     }

     world.resource_mut<Time>() = world.resource<Time<Virtual>>().as_generic()
 }

 // FixedMain schedule
 struct FixedMain {
     func run_fixed_main(world) {
         for label in world.resource<FixedMainScheduleOrder>().labels {
             world.runSchedule(label) // FixedFirst → FixedPreUpdate → FixedUpdate → FixedPostUpdate → FixedLast
         }
     }
 }

 //------------------------------------------------------------
 // Executor (simplified)
 struct Schedule {
     systems: [System]
     func run(world) { systems.forEach { $0.run(world) } }
 }
 */

//private struct CaptionColorKey: EnvironmentKey {
//    static let defaultValue = Color(.secondarySystemBackground)
//}
//extension EnvironmentValues {
//    var captionBackgroundColor: Color {
//        get { self[CaptionColorKey.self] }
//        set { self[CaptionColorKey.self] = newValue }
//    }
//}

func setupTest() {
    var coordinator = Coordinator()
    coordinator.addRessource(
        MainScheduleOrder(
            order: [
                Update.key
           ]
        )
    )

    coordinator.addSchedule(Schedule(label: Main.self, executor: SingleThreadedExecutor()))
    coordinator.addSystem(Main.self, system: MainSystem())
}

struct MainScheduleOrder {
    let order: [ScheduleLabelKey]
}

extension Coordinator {
    @usableFromInline
    var schedules: [ScheduleLabelKey: [Schedule]] {
        [:]
    }

    @usableFromInline
    var resources: [ObjectIdentifier: Any] {
        [:]
    }

    func addRessource<R>(_ ressource: R) {
    }
    func resource<R>(_ type: R.Type = R.self) -> R {
        resources[ObjectIdentifier(R.self)] as! R
    }

    func addSchedule(_ s: Schedule) {
    }

    func addSystem<S: ScheduleLabel, Sys: System>(_ s: S.Type = S.self, system: Sys) {
    }

    @inlinable @inline(__always)
    public mutating func runSchedule<S: ScheduleLabel>(_ scheduleLabel: S.Type = S.self) {
        guard let schedules = schedules[S.key] else { return }
        for schedule in schedules {
            schedule.run(&self)
        }
    }

    @inlinable @inline(__always)
    public mutating func runSchedule(_ scheduleLabelKey: ScheduleLabelKey) {
        guard let schedules = schedules[scheduleLabelKey] else { return }
        for schedule in schedules {
            schedule.run(&self)
        }
    }
}

struct MainSystem: System {
    var metadata: SystemMetadata {
        Self.metadata(from: [])
    }

    let id = SystemID(name: "Main")

    func run(coordinator: inout Coordinator, commands: inout Commands) {
        let order = coordinator.resource(MainScheduleOrder.self).order
        for order in order {
            coordinator.runSchedule(order)
        }
    }
}

public protocol ScheduleLabel: Hashable, SendableMetatype, Sendable {
    static var key: ScheduleLabelKey { get }
}

public struct ScheduleLabelKey: Hashable {
    @usableFromInline
    internal let value: ObjectIdentifier

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

extension ScheduleLabel {
    public static var key: ScheduleLabelKey {
        ScheduleLabelKey(key: ObjectIdentifier(Self.Type.self))
    }
}

public struct Main: ScheduleLabel {
    private nonisolated(unsafe) static var marker = 0

    @usableFromInline
    internal var value: Int {
        UnsafePointer(&Self.marker).hashValue
    }

    @inlinable @inline(__always)
    public func hash(into hasher: inout Hasher) {
        hasher.combine(value)
    }

    @inlinable @inline(__always)
    public static func == (lhs: Main, rhs: Main) -> Bool {
        lhs.value == rhs.value
    }
}

public struct Update: ScheduleLabel {
    private nonisolated(unsafe) static var marker = 0

    @usableFromInline
    internal var value: Int {
        UnsafePointer(&Self.marker).hashValue
    }

    @inlinable @inline(__always)
    public func hash(into hasher: inout Hasher) {
        hasher.combine(value)
    }

    @inlinable @inline(__always)
    public static func == (lhs: Update, rhs: Update) -> Bool {
        lhs.value == rhs.value
    }
}

public protocol Executor {
    func run(systems: ArraySlice<any System>, coordinator: inout Coordinator, commands: inout Commands)
}

public struct SingleThreadedExecutor: Executor {
    public func run(systems: ArraySlice<any System>, coordinator: inout Coordinator, commands: inout Commands) {
        for system in systems {
            system.run(coordinator: &coordinator, commands: &commands)
        }
    }
}

public struct Schedule {
    public let label: ScheduleLabelKey
    private let executor: any Executor
    private let systems: [any System]

    public init<L: ScheduleLabel>(label: L.Type, systems: [any System] = [], executor: any Executor) {
        self.label = label.key
        self.executor = executor
        self.systems = systems
    }

    public func run(_ coordinator: inout Coordinator) {
        var commands = Commands()
        executor.run(systems: systems[...], coordinator: &coordinator, commands: &commands)
        commands.integrate(into: &coordinator)
    }
}
