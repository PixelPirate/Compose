@testable import Components
import Testing

@Suite struct WorldClockTests {
    @Test func testWorldClockAdvancingBasic() {
        let start = SuspendingClock().now
        let world = WorldClock(instant: start)

        let advanced = world.advancing(by: 0.1)

        // Expected: unclamped (0.1 < maximumDelta 0.25), speed 1.0
        #expect(abs(advanced.delta - 0.1) < 1e-9)
        #expect(abs(advanced.elapsed - 0.1) < 1e-9)

        let wall = world.instant.duration(to: advanced.instant) / .seconds(1)
        #expect(abs(wall - 0.1) < 1e-9)
    }

    @Test func testWorldClockAdvancingCappedAndSpeed() {
        let start = SuspendingClock().now
        // Use non-default speed, keep default maximumDelta (0.25)
        let world = WorldClock(delta: 0, elapsed: 0, instant: start, isPaused: false, speed: 2.0, maximumDelta: 0.25)

        let advanced = world.advancing(by: 1.0)

        // Capped at maximumDelta (0.25) and then scaled by speed (2.0)
        let expectedDelta = 0.25 * 2.0
        #expect(abs(advanced.delta - expectedDelta) < 1e-9)
        #expect(abs(advanced.elapsed - expectedDelta) < 1e-9)

        // Instant should advance by the wall delta (1.0 seconds)
        let wall = world.instant.duration(to: advanced.instant) / .seconds(1)
        #expect(abs(wall - 1.0) < 1e-9)

        // Speed should be preserved across advancement
        #expect(abs(advanced.speed - 2.0) < 1e-12)
    }

    @Test func testWorldClockAdvancingPausedNoChange() {
        let start = SuspendingClock().now
        let world = WorldClock(delta: 0, elapsed: 0, instant: start, isPaused: true, speed: 1.0, maximumDelta: 0.25)

        let advanced = world.advancing(by: 1.0)

        // When paused, advancing should be a no-op
        #expect(abs(advanced.delta - world.delta) < 1e-12)
        #expect(abs(advanced.elapsed - world.elapsed) < 1e-12)

        let wall = world.instant.duration(to: advanced.instant) / .seconds(1)
        #expect(abs(wall - 0.0) < 1e-12)
    }
}
