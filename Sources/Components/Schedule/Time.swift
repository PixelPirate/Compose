import Foundation

struct TimeSystem: System {
    var metadata: SystemMetadata {
        Self.metadata(from: [])
    }

    let id = SystemID(name: "Time")

    func run(context: QueryContext, commands: inout Commands) {
        let clock = context.coordinator[resource: WorldClock.self]
        context.coordinator[resource: WorldClock.self] = clock.advancing(by: CFAbsoluteTime() - clock.elapsed)
    }
}

extension TimeSystem {
    static func install(into coordinator: Coordinator) {
        coordinator.addRessource(WorldClock())
        coordinator.addRessource(FixedClock())
        coordinator.addSystem(Last.self, system: TimeSystem())
    }
}

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
