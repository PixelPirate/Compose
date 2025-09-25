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

protocol Scheduler {

}
