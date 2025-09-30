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
