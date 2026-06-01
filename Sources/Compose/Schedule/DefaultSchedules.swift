public extension ScheduleLabel {
    static let main = ScheduleLabel()
    static let fixedMain = ScheduleLabel()
}

public extension ScheduleLabel {
    static let first = ScheduleLabel()
    static let preUpdate = ScheduleLabel()
    static let runFixedMainLoop = ScheduleLabel()
    static let update = ScheduleLabel()
    static let spawnScene = ScheduleLabel()
    static let postUpdate = ScheduleLabel()
    static let last = ScheduleLabel()
    static let preStartup = ScheduleLabel()
    static let startup = ScheduleLabel()
    static let postStartup = ScheduleLabel()
    static let fixedFirst = ScheduleLabel()
    static let fixedPreUpdate = ScheduleLabel()
    static let fixedUpdate = ScheduleLabel()
    static let fixedPostUpdate = ScheduleLabel()
    static let fixedLast = ScheduleLabel()

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
