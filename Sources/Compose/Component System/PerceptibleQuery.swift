import Foundation
import Perception

public final class PerceptibleQuery<each T: Component>: Perceptible, System, @unchecked Sendable
where repeat each T: ComponentResolving {
    public typealias Element = (repeat (each T).ReadOnlyResolvedType)
    public typealias Results = QueryObservationResults<repeat each T>

    public let id: SystemID; public let metadata: SystemMetadata
    let registrar = PerceptionRegistrar()
    @usableFromInline
    var runVersion: UInt64 = 0
    let storage: QueryObservationStorage<repeat each T>
    let query: Query<repeat each T>
    let diffingQuery: Query<WithEntityID>
    weak var coordinator: Coordinator?
    @usableFromInline var runCount: UInt64 = 0
    @usableFromInline var didInitialSync = false

    public init(query: Query<repeat each T>) {
        self.query = query
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

    deinit { coordinator.map { $0.remove(id) } }

    public func cancel() {
        coordinator.map { $0.remove(id) }
        coordinator = nil
    }

    public func observe(_ coordinator: Coordinator) -> Results {
        registrar.access(self, keyPath: \.runVersion)
        if coordinator !== self.coordinator {
            self.coordinator.map { $0.remove(id) }
            self.coordinator = coordinator
            didInitialSync = false
            coordinator.addSystem(self, schedule: .perceptionObservation)
        }
        return Results(storage: storage)
    }

    public func run(context: QueryContext, commands: inout Commands) {
        registrar.access(self, keyPath: \.runVersion)
        runCount &+= 1
        var changed = false
        let coord = context.coordinator

        let all = query.fetchAll(context)
        let ids = all.entityIDs

        if !didInitialSync {
            guard !ids.isEmpty else { return }
            storage.pqSync(ids, all)
            didInitialSync = true
            changed = true
        } else {
            let diffIDs = diffingQuery.fetchAll(context).entityIDs
            changed = storage.pqDelta(diffIDs: diffIDs, ids: ids, all: all)
        }

        if runCount & 0b111 == 0 || storage.count < 16 {
            var i = 0
            while i < storage.count {
                let eid = storage.entityID(at: i)
                if !coord.isAlive(eid) { storage.remove(eid); changed = true }
                else { i &+= 1 }
            }
        }

        if changed {
            registrar.withMutation(of: self, keyPath: \.runVersion) { runVersion &+= 1 }
        }
    }
}
