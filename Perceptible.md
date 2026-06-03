# PerceptibleQuery plan

## Goal

Add a `PerceptibleQuery` wrapper that lets SwiftUI views observe Compose query results through Point-Free's `Perception` package without polling and without rebuilding/copying the full result set for every component change.

```swift
import Compose
import Perception
import SwiftUI

struct MyView: View {
    let coordinator: Coordinator
    @State private var entities = PerceptibleQuery {
        Transform.self
        WithEntityID.self
    }

    var body: some View {
        WithPerceptionTracking {
            ForEach(entities.observe(coordinator), id: \.1) { transform, entityID in
                HStack {
                    Text(verbatim: String(describing: entityID))
                    Text(verbatim: String(transform.position.x))
                }
            }
        }
    }
}
```

`observe(_:)` must be cheap after the first call: it registers Perception access, ensures an internal observation system is installed, and returns a cached collection backed by observation storage.

## Current obstacles

- `Query.tracking()` is not suitable for this feature. It combines `Added` and `Changed` filters in one query, but current change filters are logical AND in `passesChangeFilters`, so `Added<C> + Changed<C> + Removed<C>` would require all changes to have happened in the same cursor window.
- Change filters depend on `QueryContext.systemTickSnapshot`. This is a good fit for an internal `System`, and a poor fit for out-of-band observation tasks.
- A coordinator notification plus full refetch design is too wasteful. A frame can contain many changed components; rebuilding a full array per notification would allocate and copy far too much.
- `Removed` tracking is incomplete for destroyed entities and slot reuse. `ComponentPool.remove(_ entityID:)` is slot-based rather than generation-aware.
- `@Perceptible` on a variadic-generic wrapper may be fragile. Prefer a manual `PerceptionRegistrar` implementation unless macro expansion is proven to compile and remain efficient.
- The build/test baseline should be rechecked before feature work and after schedule/storage refactors so performance regressions are caught early.

## Technical design

### Public API

```swift
public final class PerceptibleQuery<each T: Component>: Perceptible where repeat each T: ComponentResolving {
    public typealias Element = (repeat (each T).ReadOnlyResolvedType)
    public typealias Results = PerceptibleQueryResults<repeat each T>

    public init(
        schedule: ScheduleLabel = .perceptionObservation,
        @QueryBuilder _ content: () -> BuiltQuery<repeat each T>
    )

    public func observe(_ coordinator: Coordinator) -> Results
    public func cancel()
}
```

`Results` should be a lightweight `RandomAccessCollection` over internal storage, not a freshly allocated `[Element]` on every update. If a plain array remains the public return type, the implementation must still mutate and reuse cached array storage and must not rebuild it unless a full resync is unavoidable.

Implementation notes:

- `PerceptibleQuery` is a reference type so SwiftUI `@State` keeps one observation system and storage instance alive.
- `observe(_:)` calls `PerceptionRegistrar.access(self, keyPath: \.results)`, installs/subscribes the internal observation system if needed, performs only the initial full sync when storage is empty/uninitialized, and returns the cached collection.
- The Perception mutation should be a version bump around the cached result property, not a wholesale result recomputation.
- If `observe(_:)` is called with a different coordinator, remove the old observation system, reset storage, install on the new coordinator, and perform a full sync.
- `cancel()` and `deinit` unregister the internal system and release storage/callback references.

### Internal observation system

`PerceptibleQuery` owns an internal system registered on a dedicated observation schedule:

```swift
final class QueryObservationSystem<each T: Component>: System where repeat each T: ComponentResolving {
    let id: SystemID
    let query: Query<repeat each T>
    let storage: QueryObservationStorage<repeat each T>
    let updateCallback: @Sendable () -> Void

    var metadata: SystemMetadata { ... }

    func run(context: QueryContext, commands: inout Commands) {
        // Apply added, changed, and removed deltas to storage.
        // Call updateCallback once if storage changed.
    }
}
```

Add a default `.perceptionObservation` schedule that runs after `.last` in the main loop. This makes observation happen after normal schedules and after each schedule's deferred `Commands` have integrated. The schedule should use deterministic execution by default, or a specialized executor that allows observation systems to update their own storage without racing Perception publication.

For custom loops, document that the observation schedule must be run after all schedules that can mutate observed components.

### Storage model

Observation storage owns the cached results and applies diffs in place:

- Dense ordered storage of `(Entity.ID, Element)` rows.
- Sparse slot-to-dense index for O(1) lookup, with generation checks to avoid slot reuse bugs.
- An optional `Dictionary<Entity.ID, Int>` fallback only if sparse slot storage cannot represent required edge cases efficiently.
- A monotonically increasing storage version used only for Perception invalidation.
- Per-run deduplication so an entity changed by multiple watched components updates at most once per observation run when possible.

Storage operations:

- `upsert(id:element:)`: add new row or replace the existing element in place.
- `remove(id:)`: swap-remove or stable-remove according to the chosen ordering policy.
- `contains(id:)`: generation-aware membership check.
- `fullResync(from:)`: used only for initial load, coordinator switch, storage corruption recovery, and explicitly documented rare fallback cases.

Ordering policy must be explicit. Prefer preserving `fetchAll` order for initial sync, and document whether later inserts append or are placed according to query order. If stable query order is required after every structural change, implement an order-maintaining diff strategy without full-array rebuilds per changed entity.

### Delta query strategy

Do not combine unrelated change filters in one query. Because change filters are logical AND, each delta query must contain exactly the change filter(s) that represent one logical condition. OR behavior is achieved by running multiple narrow queries and deduplicating their entity IDs.

The observation system uses:

1. Initial full sync query:
   - User query plus a hidden `WithEntityID` if the user did not request entity IDs.
   - Populates storage once.
2. Added/upsert delta queries:
   - One query per required output or required filter component using `Added<C>`.
   - One query per excluded component using `Removed<C>` because removing an excluded component can make an entity newly match.
   - One query per optional output component using `Added<C>` because `nil -> some` changes output.
3. Changed/update delta queries:
   - One query per output component using `Changed<C>`.
   - One query per optional output component using `Changed<C>`.
   - Filter-only `With<C>` changes do not affect output or membership and should not trigger updates.
4. Removed/delete delta queries:
   - One query per required output or required filter component using `Removed<C>` to remove rows whose membership was lost.
   - One query per excluded component using `Added<C>` to remove rows whose membership was lost by gaining an excluded component.
   - One query per optional output component using `Removed<C>` to update the row to its new `nil` optional value, not remove it.

All upsert/update queries must resolve the full current output element for the entity, not only the changed component, so storage remains internally consistent.

Same-tick conflicts must be reconciled against final world membership. If an entity is removed and re-added, gains and loses an excluded component, or changes several observed components in one tick, the system must produce the final correct row exactly once.

### Hidden entity identity

Observation storage always needs `Entity.ID` even if the public query does not request it.

- If the user query already includes `WithEntityID`, use that output as the key.
- Otherwise append a hidden `WithEntityID` to internal full/delta queries and strip it from public `Element` values before storage exposure.
- Avoid duplicate `WithEntityID` query parts.

### Removal correctness

`Removed<C>` must work for observation systems:

- Removing a component from a live entity records a removal tick keyed by entity generation.
- Destroying an entity does not record removals.
- Slot reuse cannot make a removed component look like it belonged to the replacement entity.
- Re-adding a component clears stale removed state for that entity generation.
- Removed records need pruning so long-running worlds do not leak memory.

### Perception publication

The internal system calls its callback at most once per `run` when storage changed. The callback performs:

```swift
registrar.withMutation(of: self, keyPath: \.results) {
    storageVersion &+= 1
}
```

`observe(_:)` registers access to `results`; SwiftUI's `WithPerceptionTracking` rerenders when the storage version changes and then reads the updated cached collection.

Publishing should occur on the supported UI isolation domain. If observation systems can run off-main, separate storage mutation from Perception publication safely: either constrain observation publication to `MainActor`, or document and enforce same-thread/same-actor coordinator driving.

### Performance requirements

- No polling tasks.
- No full result refetch per component change.
- No full array rebuild per frame unless a full resync is explicitly required.
- `observe(_:)` is O(1) after initialization and does not query the world.
- Delta queries use existing query plan caches and sparse-set/group iteration paths.
- One Perception invalidation per observation system per schedule run, even if many entities changed.
- Deduplicate entities touched by multiple delta queries in the same run.
- Avoid `Equatable` requirements on components/results; change ticks drive updates.
- No observer overhead in worlds that do not instantiate `PerceptibleQuery`, except the presence of an empty observation schedule if added as a default schedule.

## Tickets

### Ticket 0: Confirm test/build baseline

Scope:

- Run `swift build` and `swift test` before feature work.
- Capture current performance-test numbers that are relevant to query iteration and change filters.
- Document any pre-existing warnings separately from PerceptibleQuery work.

Acceptance criteria:

- `swift build` succeeds.
- `swift test` succeeds.
- No PerceptibleQuery feature code changes are included in this ticket.

### Ticket 1: Add observation schedule support

Scope:

- Add `ScheduleLabel.perceptionObservation`.
- Install it after `.last` in `MainScheduleOrder`.
- Choose a deterministic default executor for this schedule.
- Document how custom loops must run the observation schedule after mutating schedules.

Tests:

- `.perceptionObservation` runs after `.last` in `Coordinator.run()`.
- Commands from earlier schedules are integrated before observation systems run.
- A custom direct `runSchedule(.perceptionObservation)` works.

### Ticket 2: Implement generation-safe removal tracking

Scope:

- Ensure component removals record removal ticks for every removed component.
- Ensure entity destruction does not record removal ticks.
- Make removed records generation-aware or otherwise impossible to misattribute after slot reuse.
- Clear stale removed records on re-add and prune old records safely.

Tests:

- `Removed<C>` detects `remove(C.self, from:)`.
- Destroying an entity with `C` does not record a removal visible to an observation system.
- Destroying an entity and reusing its slot does not remove or update the replacement incorrectly.
- Removing and re-adding `C` in the same tick resolves to final membership correctly.

### Ticket 3: Add internal query construction for hidden entity IDs

Scope:

- Add helpers that derive internal queries from a user query with exactly one entity ID output.
- Support both public queries that already include `WithEntityID` and those that do not.
- Strip hidden IDs from public result elements without extra per-element heap allocation.
- Note `Query.isQueryingForEntityID` and `QueryBuilder.buildExpression(_ c: WithEntityID.Type)`.

Tests:

- Query without `WithEntityID` stores rows keyed by entity ID but exposes the original element shape.
- Query with `WithEntityID` exposes the user-requested ID and does not duplicate it.
- Empty and optional-only query shapes are handled or explicitly rejected with tests.

### Ticket 4: Build observation storage

Scope:

- Implement `QueryObservationStorage<repeat each T>` or equivalent.
- Provide generation-aware O(1) `contains`, `upsert`, and `remove` operations.
- Provide a cached `RandomAccessCollection` result view suitable for SwiftUI `ForEach`.
- Define and implement ordering semantics.

Tests:

- Initial full sync populates storage.
- Upsert adds and replaces rows without rebuilding unrelated rows.
- Remove deletes only the intended generation.
- Result view reflects updates and remains safe while SwiftUI iterates at supported safe points.

### Ticket 5: Implement single-condition delta query helpers

Scope:

- Build delta query definitions without relying on OR semantics in `ChangeFilter`.
- Generate separate added, changed, and removed query lists for output, optional, required filter, and excluded filter roles.
- Ensure every update query resolves the full current output element.
- Deduplicate entity IDs touched by multiple delta queries in one run.

Tests:

- Required output add/change/remove updates storage correctly.
- Multiple output components changed in one tick update the row once to final values.
- `With<C>` add/remove changes membership; `Changed<C>` alone does not.
- `Without<C>` add removes rows and `Removed<C>` upserts rows that now match.
- Optional add/change/remove updates `nil`/`some` output without changing membership.

### Ticket 6: Implement `QueryObservationSystem`

Scope:

- Add the internal `System` owned by `PerceptibleQuery`.
- Metadata must accurately represent component reads/change filters so multi-threaded schedules do not race with mutating systems.
- Run delta queries in a deterministic order, reconcile same-tick conflicts against final membership, mutate storage, and call the callback once if changed.
- Use diffing strategy detailed in `ObservationDiffingQuery`.
- Avoid touching `Commands` except as required by the `System` protocol.

Tests:

- System applies additions, changes, removals, optional transitions, and excluded-filter transitions.
- System publishes once per run even when many entities/components changed.
- System sees deferred command mutations from prior schedules when installed in `.perceptionObservation`.
- System does not run concurrently with conflicting component writers.

### Ticket 7: Implement `PerceptibleQuery` and Perception registrar wiring

Scope:

- Add `PerceptibleQuery<repeat each T>` to the `Compose` target.
- Use manual `PerceptionRegistrar` unless `@Perceptible` is proven to compile cleanly for the variadic generic type.
- Implement `observe(_:)`, `cancel()`, deinit cleanup, coordinator switching, initial sync, system installation, and cached result return.
- Keep internal state unobserved; only the result/version property should be perceived.

Tests:

- First `observe` installs the system and returns initial results.
- Repeated `observe` without changes returns cached results and does not query the world.
- Switching coordinators unregisters from the old coordinator and resets storage.
- `cancel()` unregisters the system and allows later resubscription.

### Ticket 8: Add Perception integration tests

Scope:

- Add tests using `withPerceptionTracking`/`PerceptionRegistrar` APIs to verify that reads of `observe(_:)` are tracked and storage changes invalidate observers.
- Do not require SwiftUI rendering for core correctness.

Tests:

- A perception tracking closure that reads `observe(_:)` receives one invalidation when observation storage changes.
- No invalidation occurs for unrelated component changes that cannot affect output or membership.
- Invalidation occurs when results become empty.
- Multiple storage mutations in one observation-system run produce one invalidation.

### Ticket 9: Add SwiftUI-facing documentation examples

Scope:

- Update README or dedicated docs with correct `import Perception` usage.
- Show `@State private var query = PerceptibleQuery { ... }` and `WithPerceptionTracking` wrapping any view builder that reads `observe(_:)`.
- Document observation schedule requirements, lifetime, coordinator switching, threading expectations, and cached result semantics.

Acceptance criteria:

- Examples compile in tests or snippets where feasible.
- Documentation explains why escaping SwiftUI builders still need `WithPerceptionTracking` on older OSes.

### Ticket 10: Performance coverage

Scope:

- Add focused performance tests for observation-system overhead and diff application.
- Compare baseline query iteration with no `PerceptibleQuery` instances against worlds with inactive and active observation systems.
- Measure cached `observe(_:)`, delta-application cost, and rare full-resync cost separately.

Acceptance criteria:

- No-observation worlds remain effectively unchanged.
- Cached `observe(_:)` does not allocate after warm-up.
- Frames with sparse changes update storage substantially faster than full refetch.
- A frame with many component changes publishes once and does not rebuild the full result array per changed entity.

### Ticket 11: Concurrency and safety audit

Scope:

- Audit observation storage, callbacks, registrar usage, schedule execution, and `@Sendable` captures under Swift 6 strict concurrency.
- Decide whether `PerceptibleQuery` is `@MainActor`, internally main-actor publishing only, or explicitly same-thread-bound.
- Ensure callbacks cannot reenter coordinator mutation or corrupt storage.

Tests:

- Multi-threaded executor schedules with observation systems do not race or publish mid-stage.
- Unregistering/canceling while observation is inactive is safe.
- Coordinator deallocation with live `PerceptibleQuery` does not crash or leak.

### Ticket 12: Final integration pass

Scope:

- Run the full test suite and performance-tagged tests.
- Review public API names, access levels, inlinability, and documentation.
- Remove experimental scaffolding and ensure no polling/task leaks remain.

Acceptance criteria:

- `swift build` succeeds.
- `swift test` succeeds.
- Performance tests pass or document intentional thresholds.
- The SwiftUI example from this document compiles and updates when entities/components change.
