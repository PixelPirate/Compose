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

    init(timestep: Double = 1/64, elapsed: TimeInterval = 0, accumulated: TimeInterval = 0) {
        self.timeStep = timestep
        self.elapsed = elapsed
        self.accumulated = accumulated
    }

    mutating func expend() -> Bool { // TODO: Do I need a maximum here?
        guard accumulated >= timeStep else {
            return false
        }
        accumulated -= accumulated - timeStep
        elapsed += timeStep
        return true
    }

    mutating func accumulate(_ delta: TimeInterval) {
        accumulated += delta
    }
}
