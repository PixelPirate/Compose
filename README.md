# Compose
A Swift ECS

## SwiftUI observation with PerceptibleQuery

`PerceptibleQuery` bridges Compose query results into SwiftUI views through Point-Free's [Perception](https://github.com/pointfreeco/swift-perception) package — no polling, no full result rebuilds per frame. An internal observation system runs on a dedicated `.perceptionObservation` schedule and applies granular deltas to cached storage. SwiftUI re-renders only when the storage version changes.

### Quick start

```swift
import Compose
import Perception
import SwiftUI

struct EntityListView: View {
    let coordinator: Coordinator

    @State private var observations = PerceptibleQuery(
        query: Query {
            Transform.self
            WithEntityID.self
        }
    )

    var body: some View {
        WithPerceptionTracking {
            let results = observations.observe(coordinator)
            List(Array(results), id: \.1) { transform, entityID in
                HStack {
                    Text("Entity \(entityID.slot.rawValue):\(entityID.generation)")
                    Text("x: \(transform.position.x, format: .number.precision(.fractionLength(1)))")
                }
            }
        }
    }
}
```

### How it works

1. **Storage lives in `@State`**: `PerceptibleQuery` is a reference type. `@State` ensures one instance per view identity, so the observation system and cached results persist across re-renders.

2. **`observe(_:)` is O(1) after warm-up**: The first call installs an internal `System` on the coordinator's `.perceptionObservation` schedule, performs a full sync query, and caches the result. Subsequent calls within the same render cycle read the cached collection without querying the world.

3. **`WithPerceptionTracking` captures access**: The closure reads `observe(_:)`, which registers a Perception access on the internal version counter. When the observation system mutates storage (e.g., an entity was added or changed), the registrar invalidates observers and SwiftUI re-renders.

4. **Delta updates, not full refetches**: After the initial sync, the observation system uses a diffing query — `Or<Added, Changed, Removed>` — to detect only what changed since the last observation run. Each changed entity causes a single in-place row update. Entities whose output and membership are unchanged incur zero overhead.

### Lifetime and coordinator switching

- **`cancel()`** unregisters the internal system from the coordinator and releases storage. Call this when the view is permanently removed or you want to stop observing. The query can be reused by calling `observe(_:)` again.
- **`deinit`** automatically removes the observation system from the coordinator. No leaks.
- **Switching coordinators**: If `observe(_:)` receives a different `Coordinator` instance, the old system is unregistered, storage is reset, and a new system is installed. The next `observe(_:)` triggers a fresh full sync.

### Observation schedule

The `.perceptionObservation` schedule runs after `.last` in the main loop. This guarantees:

- All deferred `Commands` from prior schedules have been integrated.
- Spawned entities, added components, and mutations from the current frame are visible.
- Observation systems never race with component writers in the same frame.

The schedule uses a `SingleThreadedExecutor` by default. Observation systems run serially within their schedule. Custom loops must run `.perceptionObservation` after all schedules that can mutate observed components.

```swift
// Custom loop example
coordinator.runSchedule(.update)
coordinator.runSchedule(.postUpdate)
coordinator.runSchedule(.last)
coordinator.runSchedule(.perceptionObservation)  // observation last
```

### Threading expectations

- **Observation storage is mutated** on the thread that runs `.perceptionObservation` — typically the coordinator's driving thread.
- **`observe(_:)` is read** from SwiftUI's render path, usually `@MainActor`.
- Because Perception callbacks are delivered synchronously (not via `RunLoop`), the storage version bump happens while the internal system runs. Reads from `observe(_:)` on the main actor do not overlap with writes on the observation thread under single-threaded execution.
- For custom multi-threaded setups: either ensure `.perceptionObservation` runs serially, or publish Perception invalidation on `@MainActor` after the observation run completes.

### Cached result semantics

- `observe(_:)` returns a `QueryObservationResults` sequence backed by the internal storage arrays. The storage is reused; the sequence is a lightweight view, not a fresh allocation.
- The storage version increments on every structural change (add, remove, update). Perception tracks this version to detect changes.
- Iterating the results via `Array()` or `ForEach` captures the current snapshot. No CoW copy occurs during iteration.
- Empty worlds produce an empty sequence. No phantom rows.
- Entity destruction is detected through periodic liveness checks (every 8th observation run or when storage has fewer than 16 rows). Destroyed entities are silently removed from storage without a dedicated removal event.

### Why `WithPerceptionTracking` is required

On platforms that don't natively support Swift Observation (iOS <17, macOS <14), Perception uses the Objective-C runtime to bridge `willChange`/`didChange` into SwiftUI's update cycle. `WithPerceptionTracking` marks the body closure for Perception access tracking. Without it, `observe(_:)` does not register as a tracked access and changes are invisible to SwiftUI.

On newer platforms with native `Observation`, `WithPerceptionTracking` is still recommended for consistency and to avoid the `Perceptible`-vs-`Observable` bridge crash that occurs when a manually-conformant `Perceptible` type uses `PerceptionRegistrar`.

### Polling-free guarantee

- No `Timer`, `Task.sleep`, `Task { ... }`, or `Combine` publisher is created by `PerceptibleQuery`.
- No polling loop runs on the main actor or any background actor.
- Perception invalidation is push-based: the observation system calls its callback exactly once per run when storage actually changed.
- Multiple component changes in one coordinate tick produce at most one Perception invalidation — entities touched by multiple delta queries are deduplicated.

---

## Legacy query tracking

For simpler use cases that don't require the Perception stack, you can simplify change tracking by calling `.tracking()` on a `Query`. This automatically adds `Added` and `Changed` filters for every returned component (excluding backstage and excluded components), so the query only reports entities that were created or modified since the last run.

For situations where you need to know why a query returned no data, use `fetchAllWithState(_:)` or `fetchOneWithState(_:)`. These return a `QueryFetchResult` that distinguishes between:
* `.noEntities` – nothing in the world matches the query components (for example, the last entity was removed).
* `.unchanged` – matching entities exist, but none satisfied the added/changed filters during this tick.
* `.results` – the queried entities for the current tick.
