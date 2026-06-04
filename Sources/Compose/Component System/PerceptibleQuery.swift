import Foundation
import Perception

public final class PerceptibleQuery<each T: Component>: Perceptible, System, @unchecked Sendable
where repeat each T: ComponentResolving {

    public typealias Element = (repeat (each T).ReadOnlyResolvedType)
    public typealias Results = QueryObservationResults<repeat each T>

    public let id: SystemID; public let metadata: SystemMetadata
    let rg = PerceptionRegistrar(); @usableFromInline var vv: UInt64 = 0
    let st: QueryObservationStorage<repeat each T>; let qry: Query<repeat each T>; let dq: Query<WithEntityID>

    public init(query: Query<repeat each T>) {
        self.qry = query; self.dq = query.buildObservationDiffingQuery().query
        self.st = QueryObservationStorage<repeat each T>()
        self.id = SystemID(name: "PQ_\(UUID().uuidString)")
        let sc = query.schedulingMetadata
        self.metadata = SystemMetadata(readSignature: sc.readSignature.appending(query.backstageSignature), writeSignature: sc.writeSignature, excludedSignature: sc.excludedSignature, runAfter: [], resourceAccess: [], eventAccess: [])
    }

    deinit { _coord.map { $0.remove(id) } }
    public func cancel() { _coord.map { $0.remove(id) }; _coord = nil }
    public func observe(_ c: Coordinator) -> Results { rg.access(self, keyPath: \.vv); if c !== _coord { _coord.map { $0.remove(id) }; _coord = c; c.addSystem(self, schedule: .perceptionObservation) }; return Results(storage: st) }
    weak var _coord: Coordinator?

    public func run(context: QueryContext, commands: inout Commands) {
        rg.access(self, keyPath: \.vv)
        let all = Array(qry.fetchAll(context)); let ids = qry.fetchAll(context).entityIDs
        guard !ids.isEmpty else { return }
        st.pqSync(ids, all)
        rg.withMutation(of: self, keyPath: \.vv) { vv &+= 1 }
    }
}
