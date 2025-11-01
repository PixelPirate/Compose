import Foundation

struct TimeSystem: System {
    var metadata: SystemMetadata {
        Self.metadata(from: [])
    }

    static let id = SystemID(name: "Time")

    // We use a monotonic suspending clock since we want to treat the simulation as frozen when the system is suspended and
    // we also don't want any negative delta time when the systems time changes for whichever reasons.
    let clock = SuspendingClock()

    func run(context: QueryContext, commands: inout Commands) {
        let worldClock = context.coordinator[resource: WorldClock.self]
        let delta =  worldClock.instant.duration(to: clock.now) / .seconds(1)
        context.coordinator[resource: WorldClock.self] = worldClock.advancing(by: delta)
    }
}

extension TimeSystem {
    static func install(into coordinator: Coordinator) {
        coordinator.addRessource(WorldClock(instant: .now))
        coordinator.addRessource(FixedClock())
        coordinator.addSystem(.last, system: TimeSystem())
    }
}

struct WorldClock {
    let delta: TimeInterval
    let elapsed: TimeInterval
    let instant: SuspendingClock.Instant

    var isPaused = false

    var speed: Double = 1

    var maximumDelta: TimeInterval = 0.25

    init(
        delta: TimeInterval = 0,
        elapsed: TimeInterval = 0,
        instant: SuspendingClock.Instant,
        isPaused: Bool = false,
        speed: Double = 1,
        maximumDelta: TimeInterval = 0.25
    ) {
        self.delta = delta
        self.elapsed = elapsed
        self.instant = instant
        self.isPaused = isPaused
        self.speed = speed
        self.maximumDelta = maximumDelta
    }

    func advancing(by wallDelta: TimeInterval) -> WorldClock {
        guard !isPaused else {
            return self
        }

        let newWorldDelta = min(wallDelta, maximumDelta) * speed // TODO: Test if `min` is correct.
        return WorldClock(
            delta: newWorldDelta,
            elapsed: elapsed + newWorldDelta,
            instant: instant.advanced(by: .seconds(wallDelta)),
            speed: speed
        )
    }
}

struct FixedClock {
    var timeStep: Double = 1/64 //15625 micros
    @usableFromInline
    var delta: TimeInterval { timeStep }
    private(set) var elapsed: TimeInterval
    let speed: Double = 1
    private var accumulated: TimeInterval = 0

    init(timeStep: Double = 1/64, elapsed: TimeInterval = 0, accumulated: TimeInterval = 0) {
        self.timeStep = timeStep
        self.elapsed = elapsed
        self.accumulated = accumulated
    }

    mutating func expend() -> Bool { // TODO: Do I need a maximum here?
        guard let new = accumulated.checkedSubtraction(timeStep) else {
            return false
        }
        accumulated = new
        elapsed += timeStep
        return true
    }

    mutating func accumulate(_ delta: TimeInterval) {
        accumulated += delta
    }
}

extension TimeInterval {
    /// Subtracts two numbers, checking for underflow (negative result).
    /// Returns nil if the result would be < 0.
    @inlinable @inline(__always)
    func checkedSubtraction(_ other: Double) -> Double? {
        let result = self - other
        return result < 0 ? nil : result
    }
}
