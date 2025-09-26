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

    @usableFromInline
    private(set) var schedules: [ScheduleLabelKey: Schedule] = [:]

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

    @inlinable @inline(__always)
    public mutating func addSchedule(_ schedule: Schedule) {
        schedules[schedule.label] = schedule
    }

    @inlinable @inline(__always)
    public mutating func addSystem<S: ScheduleLabel>(_ s: S.Type = S.self, system: some System) {
        schedules[S.key, default: Schedule(label: S.self)].addSystem(system)
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
    MainSystem.install(into: &coordinator)
}

extension MainSystem {
    static func install(into coordinator: inout Coordinator) {
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

        TimeSystem.install(into: &coordinator)
    }
}

struct MainScheduleOrder {
    let labels: [ScheduleLabelKey]
    let startup: [ScheduleLabelKey]
}

struct FixedMainScheduleOrder {
    let labels: [ScheduleLabelKey]
}
import Atomics
struct MainSystem: System {
    private static let first = ManagedAtomic<Bool>(true)

    var metadata: SystemMetadata {
        Self.metadata(from: [])
    }

    let id = SystemID(name: "Main")

    func run(coordinator: inout Coordinator, commands: inout Commands) {
        if Self.first.exchange(false, ordering: .relaxed) {
            let order = coordinator.resource(MainScheduleOrder.self).startup
            for order in order {
                coordinator.runSchedule(order)
            }
        }
        let order = coordinator.resource(MainScheduleOrder.self).labels
        for order in order {
            coordinator.runSchedule(order)
        }
    }
}

struct FixedMainSystem: System {
    var metadata: SystemMetadata {
        Self.metadata(from: [])
    }

    let id = SystemID(name: "FixedMain")

    func run(coordinator: inout Coordinator, commands: inout Commands) {
        let order = coordinator.resource(FixedMainScheduleOrder.self).labels
        for order in order {
            coordinator.runSchedule(order)
        }
    }
}

struct TimeSystem: System {
    var metadata: SystemMetadata {
        Self.metadata(from: [])
    }

    let id = SystemID(name: "Time")

    static func install(into coordinator: inout Coordinator) {
        coordinator.addRessource(WorldClock())
        coordinator.addRessource(FixedClock())
        coordinator.addSystem(Last.self, system: TimeSystem())
    }

    func run(coordinator: inout Coordinator, commands: inout Commands) {
        let clock = coordinator[resource: WorldClock.self]
        coordinator[resource: WorldClock.self] = clock.advancing(by: CFAbsoluteTime() - clock.elapsed)
    }
}

struct RunFixedMainLoopSystem: System {
    var metadata: SystemMetadata {
        Self.metadata(from: [])
    }

    let id = SystemID(name: "RunFixedMainLoop")

    func run(coordinator: inout Coordinator, commands: inout Commands) {
        let delta = coordinator[resource: WorldClock.self].delta
        coordinator[resource: FixedClock.self].accumulate(delta)

        while coordinator[resource: FixedClock.self].expend() {
            coordinator.runSchedule(FixedMain.self)
        }
    }
}

import Foundation

struct WorldClock {
    let delta: TimeInterval
    let elapsed: TimeInterval

    var isPaused = false

    var speed: Double = 1

    var maximumDelta: TimeInterval = 0.25

    init(delta: TimeInterval = 0, elapsed: TimeInterval = 0, isPaused: Bool = false, speed: Double = 1, maximumDelta: TimeInterval = 0.25) {
        self.delta = delta
        self.elapsed = elapsed
        self.isPaused = isPaused
        self.speed = speed
        self.maximumDelta = maximumDelta
    }

    func advancing(by wallDelta: TimeInterval) -> WorldClock {
        guard !isPaused else {
            return self
        }

        let newWorldDelta = max(wallDelta, maximumDelta) * speed
        return WorldClock(
            delta: newWorldDelta,
            elapsed: elapsed + newWorldDelta,
            speed: speed
        )
    }
}

struct FixedClock {
    var timestep: Double = 1/64 //15625 micros
    @usableFromInline
    var delta: TimeInterval { timestep }
    private(set) var elapsed: TimeInterval
    let speed: Double = 1
    private var accumulated: TimeInterval = 0

    init(timestep: Double = 1/64, elapsed: TimeInterval = 0, accumulated: TimeInterval = 0) {
        self.timestep = timestep
        self.elapsed = elapsed
        self.accumulated = accumulated
    }

    mutating func expend() -> Bool { // TODO: Do I need a maximum here?
        guard accumulated >= timestep else {
            return false
        }
        accumulated -= accumulated - timestep
        elapsed += timestep
        return true
    }

    mutating func accumulate(_ delta: TimeInterval) {
        accumulated += delta
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

public struct Main: ScheduleLabel {}
public struct FixedMain: ScheduleLabel {}

public struct First: ScheduleLabel {}
public struct PreUpdate: ScheduleLabel {}
public struct RunFixedMainLoop: ScheduleLabel {}
public struct Update: ScheduleLabel {}
public struct SpawnScene: ScheduleLabel {}
public struct PostUpdate: ScheduleLabel {}
public struct Last: ScheduleLabel {}
public struct PreStartup: ScheduleLabel {}
public struct Startup: ScheduleLabel {}
public struct PostStartup: ScheduleLabel {}
public struct FixedFirst: ScheduleLabel {}
public struct FixedPreUpdate: ScheduleLabel {}
public struct FixedUpdate: ScheduleLabel {}
public struct FixedPostUpdate: ScheduleLabel {}
public struct FixedLast: ScheduleLabel {}

public protocol Executor {
    func run(systems: ArraySlice<any System>, coordinator: inout Coordinator, commands: inout Commands)
}

public struct SingleThreadedExecutor: Executor {
    public init() {
    }
    public func run(systems: ArraySlice<any System>, coordinator: inout Coordinator, commands: inout Commands) {
        for system in systems {
            system.run(coordinator: &coordinator, commands: &commands)
        }
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

    public func run(_ coordinator: inout Coordinator) {
        var commands = Commands()
        executor.run(systems: systems[...], coordinator: &coordinator, commands: &commands)
        commands.integrate(into: &coordinator)
    }

    public mutating func addSystem(_ system: some System) {
        systems.append(system)
    }
}
