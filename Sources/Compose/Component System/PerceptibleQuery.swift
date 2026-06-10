import Foundation
import os
import Perception

/// Holds a version counter properly wired for Perception observation.
/// `PerceptibleQuery` accesses this bridge through its own `registrar` to
/// avoid the `Perceptible`-vs-`Observable` bridge crash that occurs when
/// a manually-conformant type uses `PerceptionRegistrar` on platforms that
/// have native `Observation`.
@Perceptible
final class PerceptionBridge: @unchecked Sendable {
    var version: UInt64 = 0

    func bump() {
        version &+= 1
    }
}

/// An observable query that bridges Compose ECS queries to SwiftUI via Perception.
///
/// `PerceptibleQuery` owns an internal observation system that runs on the
/// `.perceptionObservation` schedule (after all other schedules). It applies
/// delta updates to a cached result set so SwiftUI views only re-render when
/// tracked components change.
///
/// ## Concurrency
///
/// - `run(context:commands:)` is nonisolated and executes on the
///   `.perceptionObservation` schedule thread. That schedule uses a
///   `SingleThreadedExecutor` so all observation systems run serially.
/// - The coordinator must be driven from a single thread or the main actor.
///   Driving `Coordinator.run()` from a background thread while calling
///   `observe(_:)` from the main actor is supported; internal shared state is
///   protected by an unfair lock.
/// - Perception publication (`registrar.withMutation`) is thread-safe and
///   may be called from the schedule thread.
/// - `observe(_:)` captures a copy-on-write snapshot of the cached elements
///   array so the returned `Results` sequence is safe to iterate even if a
///   subsequent `run` mutates storage.
public final class PerceptibleQuery<each T: Component>: System, @unchecked Sendable
where repeat each T: ComponentResolving {
    public typealias Element = (repeat (each T).ReadOnlyResolvedType)
    public typealias Results = QueryObservationResults<repeat each T>

    public let id: SystemID
    public let metadata: SystemMetadata
    let bridge = PerceptionBridge()
    let registrar = PerceptionRegistrar()
    @usableFromInline
    var runVersion: UInt64 { bridge.version }
    let storage: QueryObservationStorage<repeat each T>
    let query: Query<repeat each T>
    let diffingQuery: Query<WithEntityID>
    private let lock = OSAllocatedUnfairLock()
    private var _didInitialSync = false
    private weak var _coordinator: Coordinator?
    @usableFromInline var runCount: UInt64 = 0

    public init(query: Query<repeat each T>) {
        self.query = query.withGeneration()
        self.diffingQuery = query.buildObservationDiffingQuery().query
        self.storage = QueryObservationStorage<repeat each T>()
        self.id = SystemID(name: "PerceptibleQuery_\(UUID().uuidString)")
        let systemMetadata = query.schedulingMetadata
        self.metadata = SystemMetadata(
            readSignature: systemMetadata.readSignature.appending(query.backstageSignature),
            writeSignature: systemMetadata.writeSignature,
            excludedSignature: systemMetadata.excludedSignature,
            runAfter: [],
            resourceAccess: [],
            eventAccess: []
        )
    }

    deinit {
        lock.lock()
        let coord = _coordinator
        _coordinator = nil
        lock.unlock()
        coord?.remove(id)
    }

    /// Unregisters the internal observation system from the coordinator.
    ///
    /// After calling `cancel()`, subsequent calls to `observe(_:)` will
    /// re-register and perform a fresh full sync. Safe to call when no
    /// observation is active.
    public func cancel() {
        lock.lock()
        let coord = _coordinator
        _coordinator = nil
        _didInitialSync = false
        lock.unlock()
        coord?.remove(id)
    }

    /// Returns a snapshot of the current observation results and ensures the
    /// internal observation system is registered on `coordinator`.
    ///
    /// - Parameter coordinator: The world to observe. If this differs from the
    ///   previously observed coordinator, the old observation system is
    ///   unregistered and a new one is installed.
    /// - Returns: A `Results` sequence backed by a copy-on-write snapshot of
    ///   the cached elements. Safe to iterate in SwiftUI `ForEach`.
    public func observe(_ coordinator: Coordinator) -> Results {
        registrar.access(bridge, keyPath: \.version)

        lock.lock()
        let coordinatorChanged = coordinator !== _coordinator
        if coordinatorChanged {
            let oldCoordinator = _coordinator
            _coordinator = coordinator
            _didInitialSync = false
            lock.unlock()
            oldCoordinator?.remove(id)
            coordinator.addSystem(self, schedule: .perceptionObservation)
        } else {
            lock.unlock()
        }

        // Snapshot under lock to avoid racing with run()'s writes to storage.
        lock.lock()
        let elements = storage.elements
        let version = storage.storageVersion
        lock.unlock()
        return Results(elements: elements, storageVersion: version)
    }

    public func run(context: QueryContext, commands: inout Commands) {
        registrar.access(bridge, keyPath: \.version)
        runCount &+= 1
        var changed = false
        let coord = context.coordinator

        let all = query.fetchAll(context)
        let ids = all.entityIDs

        lock.lock()
        let needsInitialSync = !_didInitialSync
        lock.unlock()

        if needsInitialSync {
            guard !ids.isEmpty else { return }
            lock.lock()
            storage.pqSync(ids, all)
            _didInitialSync = true
            changed = true
            lock.unlock()
        } else {
            let diffIDs = diffingQuery.fetchAll(context).entityIDs
            lock.lock()
            changed = storage.pqDelta(diffIDs: diffIDs.span, ids: ids, all: all)
            lock.unlock()
        }

        if runCount & 0b111 == 0 || storage.count < 16 {
            lock.lock()
            var i = 0
            while i < storage.count {
                let eid = storage.entityID(at: i)
                if !coord.isAlive(eid) { if storage.remove(eid) { changed = true } }
                else { i &+= 1 }
            }
            lock.unlock()
        }

        if changed {
            if Thread.isMainThread {
                registrar.withMutation(of: bridge, keyPath: \.version) {
                    bridge.bump()
                }
            } else {
                DispatchQueue.main.async { [registrar, bridge] in
                    registrar.withMutation(of: bridge, keyPath: \.version) {
                        bridge.bump()
                    }
                }
            }
        }
    }
}
