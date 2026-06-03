import Foundation

@usableFromInline
final class QueryObservationSystem<each T: Component>: System, @unchecked Sendable
where repeat each T: ComponentResolving {

    @usableFromInline let id: SystemID
    @usableFromInline let _meta: SystemMetadata
    @usableFromInline var runCount: UInt64
    @usableFromInline var didInitialSync: Bool
    @usableFromInline let syncBlock: @Sendable (QueryContext) -> Bool
    @usableFromInline let deltaBlock: @Sendable (QueryContext) -> Bool
    @usableFromInline let storage: QueryObservationStorage<repeat each T>
    @usableFromInline let callback: @Sendable () -> Void

    @usableFromInline
    var metadata: SystemMetadata { _meta }

    @usableFromInline
    init(
        id: SystemID,
        metadata: SystemMetadata,
        storage: QueryObservationStorage<repeat each T>,
        syncBlock: @Sendable @escaping (QueryContext) -> Bool,
        deltaBlock: @Sendable @escaping (QueryContext) -> Bool,
        callback: @Sendable @escaping () -> Void
    ) {
        self.id = id
        self._meta = metadata
        self.storage = storage
        self.syncBlock = syncBlock
        self.deltaBlock = deltaBlock
        self.callback = callback
        self.runCount = 0
        self.didInitialSync = false
    }

    @usableFromInline
    func run(context: QueryContext, commands: inout Commands) {
        runCount &+= 1
        var changed = false
        let coord = context.coordinator

        if !didInitialSync {
            changed = syncBlock(context)
            didInitialSync = true
        } else {
            changed = deltaBlock(context)
        }

        if runCount & 0b111 == 0 || storage.count < 16 {
            var i = 0
            while i < storage.count {
                let eid = storage.entityID(at: i)
                if !coord.isAlive(eid) { storage.remove(eid); changed = true }
                else { i &+= 1 }
            }
        }

        if changed { callback() }
    }
}