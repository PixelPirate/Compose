import Testing
import Compose
import Observatory
import Foundation

/// Mirrors `PerceptibleQueryConcurrencyTests`, but exercises `ObservationQuery`
/// (driven by the self-contained `Observatory` package) instead of
/// `PerceptibleQuery`. Reuses `StorageTestComponent` from the perceptible suite.
@Suite struct ObservationQueryTests {

    @MainActor @Test func initialObserveSyncsAfterRun() {
        let coordinator = Coordinator()
        installPerception(into: coordinator)
        let query = ObservationQuery(query: Query { StorageTestComponent.self })

        _ = coordinator.spawn(StorageTestComponent(value: 1))
        _ = coordinator.spawn(StorageTestComponent(value: 2))

        _ = query.observe(coordinator)
        coordinator.run()

        #expect(query.observe(coordinator).count == 2)
    }

    @MainActor @Test func multiThreadedRunDoesNotRace() async {
        let coordinator = Coordinator()
        installPerception(into: coordinator)
        let query = ObservationQuery(query: Query { StorageTestComponent.self })

        for i in 0..<100 {
            _ = coordinator.spawn(StorageTestComponent(value: i))
        }

        _ = query.observe(coordinator)

        let iterations = 50
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let thread = Thread {
                for _ in 0..<iterations {
                    coordinator.run()
                }
                continuation.resume()
            }
            thread.start()
        }

        #expect(query.observe(coordinator).count == 100)
    }

    @MainActor @Test func cancelWhileInactiveIsSafe() {
        let coordinator = Coordinator()
        let query = ObservationQuery(query: Query { StorageTestComponent.self })

        query.cancel()

        _ = coordinator.spawn(StorageTestComponent(value: 1))
        _ = query.observe(coordinator)
        coordinator.run()
        query.cancel()
        query.cancel()
    }

    @MainActor @Test func cancelAndReobserveWorks() {
        let coordinator = Coordinator()
        installPerception(into: coordinator)
        let query = ObservationQuery(query: Query { StorageTestComponent.self })
        _ = coordinator.spawn(StorageTestComponent(value: 42))

        _ = query.observe(coordinator)
        coordinator.run()
        #expect(query.observe(coordinator).count == 1)

        query.cancel()
        _ = query.observe(coordinator)
        coordinator.run()
        #expect(query.observe(coordinator).count == 1)
    }

    @MainActor @Test func observeReturnsIndependentSnapshot() {
        let coordinator = Coordinator()
        installPerception(into: coordinator)
        let query = ObservationQuery(query: Query { StorageTestComponent.self })

        _ = coordinator.spawn(StorageTestComponent(value: 10))
        _ = query.observe(coordinator)
        coordinator.run()

        let results1 = query.observe(coordinator)
        #expect(results1.count == 1)

        _ = coordinator.spawn(StorageTestComponent(value: 20))
        coordinator.run()

        #expect(results1.count == 1)
        #expect(query.observe(coordinator).count == 2)
    }

    /// Validates the Observatory bridge: a change to the observed world fires a
    /// `withObservationTracking` callback that read `observe(_:)`.
    @MainActor @Test func mutationNotifiesObservationTracking() async {
        let coordinator = Coordinator()
        installPerception(into: coordinator)
        let query = ObservationQuery(query: Query { StorageTestComponent.self })

        _ = query.observe(coordinator)
        coordinator.run()

        let notified = ManagedBox(false)
        withObservationTracking {
            _ = query.observe(coordinator)
        } onChange: {
            notified.value = true
        }

        // Mutate the world and run the observation schedule; the bridge bumps
        // its version on the main thread, triggering the tracking callback.
        _ = coordinator.spawn(StorageTestComponent(value: 7))
        coordinator.run()

        // Version bump is dispatched to the main queue when off-thread; here we
        // run on the main actor / main thread so it is synchronous.
        #expect(notified.value == true)
    }

    struct StorageTestComponent: Component, Equatable {
        static let componentTag = ComponentTag.makeTag()
        var value: Int
    }

    /// Mirrors the SpacerRun game loop: an existing entity's component changes
    /// every frame, and the view re-registers tracking each frame (like the UI
    /// reconciler). Every frame must both update storage AND fire the change
    /// notification. This is the scenario that fails in release builds.
    @MainActor @Test func continuousComponentChangesNotifyEachFrame() {
        let coordinator = Coordinator()
        installPerception(into: coordinator)
        let query = ObservationQuery(query: Query { StorageTestComponent.self })
        let entity = coordinator.spawn(StorageTestComponent(value: 0))

        _ = query.observe(coordinator)
        coordinator.run()
        #expect(query.observe(coordinator).count == 1)

        for frame in 1...8 {
            let notified = ManagedBox(false)
            withObservationTracking {
                _ = query.observe(coordinator)
            } onChange: {
                notified.value = true
            }

            // Mutate the existing entity's component (replace pattern marks it changed).
            coordinator.remove(StorageTestComponent.self, from: entity)
            coordinator.add(StorageTestComponent(value: frame), to: entity)
            coordinator.run()

            let observed = Array(query.observe(coordinator)).first?.value
            #expect(observed == frame, "frame \(frame): storage value")
            #expect(notified.value == true, "frame \(frame): change notification")
        }
    }
}

/// A minimal `Sendable` reference cell for capturing state inside the
/// `@Sendable` `onChange` closure.
private final class ManagedBox<Value>: @unchecked Sendable {
    var value: Value
    init(_ value: Value) { self.value = value }
}
