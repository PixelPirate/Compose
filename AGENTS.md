# AGENTS.md — Compose

A high-performance Swift ECS (Entity Component System) library using Swift 6 strict concurrency, variadic generics, and lock-free patterns.

## Build & Test

```bash
swift build              # Build the library (debug)
swift build -c release   # Release build
swift test               # Run all tests (ComposeTests + ComposePerformanceTests)
swift test --filter "testName"  # Run a specific test
```

Targets: `Compose` (library), `ComposeTests` (unit), `ComposePerformanceTests` (tagged `@Tag.performance`).

## Architecture

All public API flows through **`Coordinator`** — the central world instance. It owns:
- **`ComponentPool`** — maps `ComponentTag` → `AnyComponentArray` (sparse-set based storage)
- **`IndexRegistry`** — entity slot allocation with generational IDs
- **`SystemManager`** — registry of systems mapped to named schedules
- **`EventManager`** — per-event-type ring buffers with reader state tracking
- **`Groups`** — owned/non-owning groups that pack entities into contiguous dense storage
- **`entitySignatures`** — `ContiguousArray<ComponentSignature>` indexed by `SlotIndex`
- **`resources`** — `[ResourceKey: Any]` dictionary with version clock
- Three **query caches** (`signatureQueryCache`, `sparseQueryCache`, `slotsQueryCache`) per-query-hash, reuse plan objects across frames

### Core Loop

```
Coordinator.run()
  → runSchedule(.main)
    → MainSystem iterates schedule labels in MainScheduleOrder
      → each Schedule.run()
        → Executor.run(systems, coordinator, &commands)
          → system.run(context: QueryContext, commands: &Commands)
        → commands.integrate(into: coordinator)  // deferred mutations
```

Systems never mutate the world directly. They queue deferred work in `Commands` (add/remove components, spawn/destroy entities, send events). Commands are integrated after all systems in a stage complete. This is critical for correctness during concurrent execution.

### Entity ID

```swift
public struct Entity.ID: Hashable, Sendable {
    let slot: SlotIndex      // index into entity arrays
    let generation: UInt32   // prevents ABA reuse
}
```

`SlotIndex` is `RawRepresentable<Array.Index>`. When an entity is destroyed, its slot is recycled but generation advances. `Coordinator.isAlive(_:)` checks `indices[generationFor: slot] == generation`.

### Component

Conform types to `Component`:
```swift
public protocol Component: ComponentResolving, SendableMetatype {
    static var componentTag: ComponentTag { get }
    static var storage: ComponentStorage { get }  // default: .sparseSet
}
```

A `ComponentTag` is an auto-incrementing integer (atomic counter). Every component type gets a unique tag lazily.

### Query System

Queries use Swift's variadic generics and a `@resultBuilder` DSL:

```swift
Query {
    Write<Transform>.self   // writable, yields Write<Transform> wrapper
    Gravity.self            // read-only, yields Gravity value
    With<RigidBody>.self    // required filter, not in output tuple
    Without<Static>.self    // exclusion filter
    Added<Health>.self      // change filter: component just added
    Changed<Health>.self    // change filter: component mutated
    WithEntityID.self       // yields Entity.ID in output
    Optional<Name>.self     // optional component
}
```

**Filter types** (`With`, `Without`, `Added`, `Changed`, `Removed`) contribute to the query's signature/change filters but don't produce output tuple elements. They use `Never` as the QueriedComponent to signal "no output" in the parameter pack.

**Query parts convention**: types in `Component System/Query Parts/` implement `ComponentResolving` with `QueriedComponent = Never` to indicate they are filters only.

**Execution strategies**:
1. **Signature plan** — bitmap-based filter on entity signatures (fast, no storage access). Used when query only has signature-level constraints.
2. **Sparse plan** — smallest component array as base, checks membership in other sparse sets. Used for queries with 2+ required components where no group matches.
3. **Slots plan** — uses a pre-built **Group** with contiguous dense storage for owned components. Iterates a dense slice prefix `[0..<group.size)` with direct index access.

Query plans are **cached per `QueryHash`** (hash of include + exclude signatures). Plans are rebuilt when component storage changes shape.

### Groups

Groups pack entities matching a query into contiguous dense storage for cache-friendly iteration:

```swift
coordinator.addGroup {
    Transform.self          // owned — gets packed contiguously
    With<Material>.self     // included filter
    Without<RigidBody>.self // excluded filter
}
```

- **Owning group** (`Group`) — if the query has write components, it takes ownership of those tags. Can't overlap with another owning group.
- **Non-owning group** (`NonOwningGroup`) — read-only queries only, any number can overlap.

When a matching entity is spawned or a component added, groups update their packed partition. Groups are rebuilt by repartitioning the primary component's dense storage (swap-least-owned-component heuristic).

### Schedules & Executors

`Schedule` = `[System]` + `Executor`. Default schedule labels:
- **Main loop**: `first → preUpdate → runFixedMainLoop → update → spawnScene → postUpdate → last`
- **Fixed timestep**: `fixedFirst → fixedPreUpdate → fixedUpdate → fixedPostUpdate → fixedLast`
- **Startup**: `preStartup → startup → postStartup` (runs once, on first main tick)

**Executors**:
- `SingleThreadedExecutor` — serial execution, default for `.main` schedule
- `MultiThreadedExecutor` — greedy **stage packing**: `Stagehand` builds conflict-free stages (no overlapping write signatures, resource writes, or event writes). Systems within a stage run in parallel via `DispatchQueue.concurrentPerform`. Stages are cached.
- `UnsafeUncheckedMultiThreadedExecutor` — everything in parallel, no conflict checking

### Resources

Type-keyed singletons stored in `Coordinator.resources`:
```swift
coordinator.addResource(MyConfig(...))
let cfg: MyConfig = context.resource()
context[resource: WorldClock.self] = clock.advancing(by: dt)
```

Every resource mutation increments `resourceClock`. Snapshots (`ResourceVersionSnapshot`) enable change detection across frames.

### Events

Simple typed event channels:
```swift
struct CollisionEvent: Event { let a, b: Entity.ID }
// In system:
context.send(CollisionEvent(a: e1, b: e2))
// Reading:
var state = EventReaderState<CollisionEvent>()
for event in context.readEvents(CollisionEvent.self, state: &state) { ... }
// Or drain all:
for event in context.drainEvents(CollisionEvent.self) { ... }
```

### Change Tracking & Ticks

`Coordinator.changeTick` increments once per system execution. `worldVersion` increments on entity mutation. `SystemTickRecord` tracks per-system last-run/this-run ticks. Change filters (`Added`, `Changed`, `Removed`) compare entity-level component ticks against the system's last-run tick.

For SwiftUI bridging: `.tracking()` on a `Query` auto-adds `Added` + `Changed` filters. `fetchAllWithState` / `fetchOneWithState` return `QueryFetchResult` distinguishing `.noEntities`, `.unchanged`, `.results`.

## Code Patterns & Conventions

### Concurrency

- Swift 6 strict mode (`swiftLanguageModes: [.v6]`)
- Extensive use of `@usableFromInline`, `@inlinable @inline(__always)` for performance
- `OSAllocatedUnfairLock` for cache locks and resource locks (not actors — performance-critical paths)
- `nonisolated(unsafe)` for `DispatchQueue.concurrentPerform` captures and atomic-access bypass
- `UnsafeSendable<T>` / `UnsafeMutableSendable<T>` wrapper for bridging non-Sendable types through `@Sendable` closures
- `ManagedAtomic` from swift-atomics for lock-free counters (component tags, tick flags)
- `Synchronization` module imported where needed for atomics API

### Storage Details

- Components stored as **sparse sets** with separate dense/sparse arrays per component type
- `ComponentArray<C>` — typed wrapper around dense storage + sparse mapping
- `AnyComponentArray` — type-erased access to the above (used by `ComponentPool`)
- `SparseSet+SparseArray` — custom sparse array with page-based growing (configurable page size)
- `SparseSet+Paging` — page-based allocation for sparse arrays, growth doubles page capacity up to a max
- `BitSet` — custom bitmap for component signatures (alternative compile flag: `BITSET_USE_DYNAMIC_ARRAY`)
- `ContiguousSpan<T>`, `SlotsSpan<I,T>`, `MutableContiguousSpan<T>` — unsafe pointer-based span types for zero-overhead iteration

### Command Pattern

System closures receive `inout Commands`. All world mutations go through commands — component add/remove, entity spawn/destroy, event send, arbitrary closures. Commands are collected and batch-applied after stage execution. This guarantees no interleaved mutation during parallel system execution or query iteration.

### Macro (Disabled)

`SystemAutoMacro.swift` and `SystemAutoMacro 2.swift` are **disabled** (commented-out experimental implementations of a `@SystemAuto` macro). Do not use or modify unless explicitly needed.

### Test Fixtures

Test files define their own component types (`Transform`, `Gravity`, `Person`, `Vector3`) inline — they don't import component types from the library. Both `ComposeTests` and `ComposePerformanceTests` duplicate these definitions.

Tests use `swift-testing` (`@Test`, `#expect`, `#require`), not XCTest.

### Naming

- **Source module**: `Compose` (product name in Package.swift)
- **Test imports**: use the module name as declared in the target dependency — check actual import statements in tests
- Swift files use PascalCase, folder names use spaces (e.g., `Query Parts/`, `Component System/`)
- `Coordinator` not `World` or `ECSWorld`
- `System` protocol, not `TickSystem` or `UpdateSystem`

## Gotchas

1. **Commands are deferred**: Component mutations in `commands.add(...)` don't take effect until `commands.integrate(into:)`. You cannot query for a component you just added via commands in the same system tick.

2. **Entity generation checks**: Always use `coordinator.isAlive(id)` before accessing components on a stored entity ID. Slots get recycled.

3. **Group conflicts**: Two owning groups cannot share any component tag. Attempting to register an overlapping owning group throws `GroupAcquireError` (currently just crashes via `try!`).

4. **Query plan caching**: Plans are cached by hash of `(include signature, exclude signature)`. If you create the same query from different types but with identical signatures, they share plans. Adding components changes storage shape and invalidates cached plans.

5. **MainSystem.reset()**: Call this between test cases that create their own coordinators. The `MainSystem.first` atomic flag persists across coordinator instances in the same process.

6. **Fixed timestep**: `WorldClock` resource controls time. Default maximum delta is 0.25s, speed defaults to 1.0. `FixedMainSystem` accumulates time and runs the fixed schedule in discrete timestep-sized batches.

7. **No XCTest**: All testing uses Swift Testing (`import Testing`). `@Test` functions, not `test*()` methods in `XCTestCase` subclasses.

8. **Strict Sendable**: Swift 6 mode means you'll hit Sendable warnings on unsafe pointer spans. The project uses `@Sendable` closures with `nonisolated(unsafe)` and `UnsafeSendable` wrappers — don't change the Sendable strategy without understanding the concurrency model.