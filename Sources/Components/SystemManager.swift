@usableFromInline
struct SystemManager {
    @usableFromInline
    internal var systems: [SystemID: any System] = [:]

    @usableFromInline
    internal var metadata: [SystemID: SystemMetadata] = [:]

    @usableFromInline
    private(set) var schedules: [ScheduleLabel: Schedule] = [:]

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
    public mutating func addSystem(_ label: ScheduleLabel, system: some System) {
        schedules[label, default: Schedule(label: label)].addSystem(system)
    }
}
