# Performance-Critical Code Rules

This codebase is designed for extreme performance. Correctness alone is insufficient. Any change that increases CPU time, memory traffic, cache misses, branch mispredictions, synchronization overhead, or allocation frequency should be treated as a bug unless explicitly justified.

When implementing features, prioritize:

1. Cache locality
2. Predictable execution
3. Allocation avoidance
4. Minimal memory traffic
5. Minimal synchronization
6. Inlining opportunities
7. SIMD/vectorization opportunities

The code should resemble systems programming more than typical application-level Swift.

---

# Profiling First

Never assume a change is faster.

Before introducing a new abstraction, data structure, synchronization mechanism, or algorithm:

- Identify the hot path.
- Estimate the cost in allocations, branches, cache misses, and synchronization.
- Prefer measured performance over theoretical cleanliness.
- Favor simpler machine code over cleaner-looking source code.

A small amount of duplicated code is preferable to an abstraction that blocks optimization.

---

# CPU Cache Rules

Modern CPUs are usually limited by memory latency rather than arithmetic throughput.

Prefer:

- Contiguous memory layouts.
- Sequential memory access.
- Structure-of-Arrays (SoA) when iterating over a subset of fields.
- Dense arrays instead of pointer-linked structures.
- Flat storage instead of object graphs.

Avoid:

- Linked lists.
- Deep object hierarchies.
- Pointer chasing.
- Excessive heap allocation.
- Random memory access patterns.

When designing data structures, think in cache lines (typically 64 bytes), not objects.

A single cache miss can cost more than hundreds of arithmetic instructions.

Cache locality is often more important than algorithmic elegance. Research and production systems repeatedly show that cache-friendly layouts can outperform theoretically superior data structures by large margins. ([arXiv](https://arxiv.org/abs/2507.21492?utm_source=chatgpt.com))

---

# Branch Prediction Rules

Branches are expensive when they are unpredictable.

Prefer:

- Branchless algorithms where practical.
- Data layouts that create predictable execution paths.
- Hot-path specialization.
- Separating common and rare cases.

Avoid:

- Frequently alternating conditions.
- Deep conditional nesting.
- Virtual dispatch inside tight loops.
- Error handling mixed into hot paths.

Cold paths should be separated from hot paths whenever possible.

---

# Allocation Rules

Heap allocation is expensive.

Avoid allocations in hot paths.

Prefer:

- Preallocated storage.
- Reusable buffers.
- Fixed-capacity structures.
- Arena-style allocation patterns when appropriate.

Every allocation potentially introduces:

- allocator overhead
- cache pollution
- ARC traffic
- memory fragmentation

Repeated allocation inside loops is usually unacceptable.

---

# ARC Rules

ARC is not free.

Retain/release traffic frequently becomes a major cost in optimized Swift code. ([apple-swift.readthedocs.io](https://apple-swift.readthedocs.io/en/latest/ARCOptimization.html?utm_source=chatgpt.com))

Avoid:

- Unnecessary reference types.
- Temporary class instances.
- Closure captures in hot paths.
- APIs that create ownership churn.

Prefer:

- Value semantics where possible.
- Stable ownership structures.
- Long-lived objects instead of frequently created objects.

When evaluating performance, inspect retain/release activity in Instruments.

---

# Copying Rules

Never assume a value type is cheap.

Swift collections use Copy-on-Write (CoW). While this avoids immediate deep copies, mutations can trigger expensive copies. ([Amit Sen](https://www.amitsen.de/blog/swift-copy-on-write-performance?utm_source=chatgpt.com))

Be suspicious of:

- Array mutations in hot loops.
- Large struct copies.
- Returning large collections repeatedly.
- Hidden CoW boundaries.

Avoid accidental copying.

Pass large values using borrowing patterns where practical.

Review generated code if uncertain.

---

# Data Structure Selection

Default choices:

- Array over linked structures.
- Flat buffers over trees.
- Dense storage over sparse storage.
- Integer identifiers over object references.

Do not introduce:

- Linked lists
- General-purpose graph structures
- Boxed values
- Type-erased containers

unless profiling demonstrates a clear win.

---

# Protocol and Existential Rules

Avoid protocol existentials in performance-critical code.

Do not write:

```swift
var value: any SomeProtocol
```

inside hot paths.

Existentials introduce:

- witness table lookups
- dynamic dispatch
- larger runtime representations
- additional optimization barriers

They can also force runtime exclusivity checks. ([docs.swift.org](https://docs.swift.org/compiler/documentation/diagnostics/existential-type/?utm_source=chatgpt.com))

Prefer:

```swift
func process<T: SomeProtocol>(_ value: T)
```

over:

```swift
func process(_ value: any SomeProtocol)
```

Use generics whenever possible.

---

# Dispatch Rules

Prefer static dispatch.

Avoid:

- dynamic dispatch
- protocol existentials
- unnecessary subclassing
- Objective-C runtime dispatch

Use:

- structs
- enums
- final classes
- generics

whenever practical.

The optimizer performs substantially better when concrete types are known.

---

# Inlining Rules

Function calls are not free.

Small hot-path functions should be designed so the optimizer can inline them.

However:

- Do not blindly add `@inline(__always)`.
- Excessive forced inlining can increase code size and reduce instruction-cache efficiency. ([Swift Forums](https://forums.swift.org/t/low-level-swift-optimization-tips/37917?utm_source=chatgpt.com))

Write code that is naturally easy to inline.

Use forced inlining only when profiling proves it is beneficial.

---

# Closure Rules

Closures frequently introduce hidden costs.

Be careful with:

- escaping closures
- captured state
- callback-heavy designs

Avoid closures inside tight loops.

Prefer direct control flow where possible.

---

# Synchronization Rules

Synchronization is expensive.

Avoid:

- locks
- mutexes
- actors
- atomics

on hot paths unless required.

When synchronization is necessary:

1. Minimize contention.
2. Minimize synchronization frequency.
3. Prefer ownership transfer over shared mutable state.
4. Consider lock-free approaches only when complexity is justified.

False sharing must also be considered.

Frequently modified values accessed by multiple threads should not occupy the same cache line. ([Swift Forums](https://forums.swift.org/t/is-there-any-way-to-ensure-vars-atomics-are-laid-out-on-separate-cache-lines/65268?utm_source=chatgpt.com))

---

# Concurrency Rules

Parallelism is not automatically faster.

Additional threads can introduce:

- cache invalidation
- synchronization costs
- memory bandwidth contention
- worse locality

Only parallelize work that is sufficiently large.

Preserve locality whenever possible.

---

# Unsafe APIs

Performance-critical sections may use:

```swift
UnsafePointer
UnsafeMutablePointer
UnsafeBufferPointer
UnsafeMutableBufferPointer
ManagedBuffer
```

when justified.

Safety abstractions may be bypassed if:

1. A measurable performance benefit exists.
2. The implementation remains correct.
3. The unsafe region remains isolated and documented.

Avoid introducing additional safety layers around already-proven hot-path code.

---

# Swift-Specific Performance Pitfalls

Avoid:

- `any Protocol`
- unnecessary `Any`
- type erasure
- frequent ARC ownership changes
- hidden CoW copies
- allocation-heavy collection transformations
- chained higher-order functions in hot paths
- unnecessary async boundaries
- excessive actor hopping

Be suspicious of:

```swift
map
filter
reduce
flatMap
compactMap
```

inside critical loops.

A hand-written loop is often significantly easier for the optimizer.

---

# API Design Rules

When designing APIs:

Prefer:

```swift
mutating func update(...)
```

over:

```swift
func updated(...) -> NewValue
```

when copying would occur.

Prefer:

```swift
inout
```

when ownership is clear.

Prefer explicit mutation over hidden allocation.

---

# What AI Agents Must Not Do

Do not introduce any of the following without explicit justification:

- New protocol abstractions.
- New existential types.
- Additional heap allocations.
- New locks.
- Additional actors.
- Closure-heavy APIs.
- Type-erasure layers.
- Object-oriented hierarchies.
- Convenience wrappers around hot-path code.
- Intermediate collections.
- Additional copies of large values.

Assume every abstraction has a runtime cost until proven otherwise.

The simplest generated machine code is usually preferred over the cleanest-looking Swift source.
