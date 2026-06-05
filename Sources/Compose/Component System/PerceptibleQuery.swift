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

    public func cancel() {
        coordinator.map { $0.remove(id) }
        coordinator = nil
    }

    public func observe(_ coordinator: Coordinator) -> Results {
        registrar.access(self, keyPath: \.runVersion)
        if coordinator !== self.coordinator {
            self.coordinator.map { $0.remove(id) }
            self.coordinator = coordinator
            coordinator.addSystem(self, schedule: .perceptionObservation)
        }
        return Results(storage: storage)
    }

    public func run(context: QueryContext, commands: inout Commands) {
        registrar.access(self, keyPath: \.runVersion)
        let all = query.fetchAll(context)
        let ids = all.entityIDs
        guard !ids.isEmpty else { return }
        storage.pqSync(ids, all)
        registrar.withMutation(of: self, keyPath: \.runVersion) { runVersion &+= 1 }
    }
}
