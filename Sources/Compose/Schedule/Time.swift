import Foundation

struct TimeSystem: System {
    var metadata: SystemMetadata {
        Self.metadata(from: [])
    }

    let id = SystemID(name: "Time")

    // We use a monotonic suspending clock since we want to treat the simulation as frozen when the system is suspended and
    // we also don't want any negative delta time when the systems time changes for whichever reasons.
    let clock = SuspendingClock()

    func run(context: QueryContext, commands: inout Commands) {
        context.coordinator.withResource(WorldClock.self) { worldClock in
            let delta =  worldClock.instant.duration(to: clock.now) / .seconds(1)
            worldClock.advance(by: delta)
        }
    }
}

extension TimeSystem {
    static func install(into coordinator: Coordinator) {
        coordinator.addResource(WorldClock(instant: .now))
        coordinator.addResource(FixedClock())
        coordinator.addSystem(TimeSystem(), schedule: .last)
    }
}

public struct WorldClock: Equatable {
    public private(set) var delta: TimeInterval
    public private(set) var elapsed: TimeInterval
    public private(set) var instant: SuspendingClock.Instant

    public var isPaused = false

    public var speed: Double = 1

    var maximumDelta: TimeInterval = 0.25

    public init(
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

    mutating func advance(by wallDelta: TimeInterval, clamped: Bool = true) {
        guard !isPaused else {
            return
        }

        let newWorldDelta = (clamped ? min(wallDelta, maximumDelta) : wallDelta) * speed // TODO: Test if `min` is correct.

        self.delta = newWorldDelta
        self.elapsed = elapsed + newWorldDelta
        self.instant = instant.advanced(by: .seconds(wallDelta))
    }

    func advancing(by wallDelta: TimeInterval, clamped: Bool = true) -> WorldClock {
        var new = self
        new.advance(by: wallDelta, clamped: clamped)
        return new
    }
}

public struct FixedClock {
    var timeStep: Double = 1/64 //15625 micros
    public var delta: TimeInterval { timeStep }
    private(set) var elapsed: TimeInterval
    public let speed: Double = 1
    private var accumulated: TimeInterval = 0

    public init(timeStep: Double = 1/64, elapsed: TimeInterval = 0, accumulated: TimeInterval = 0) {
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
