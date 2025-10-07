@usableFromInline
struct ScheduledStage {
    @usableFromInline
    let systems: [System]
}

@usableFromInline
final class Stagehand {
    private let systems: ArraySlice<any System>

    @usableFromInline
    init(systems: ArraySlice<any System>) {
        self.systems = systems
    }

    /// Greedy packing into conflict-free parallel stages
    @usableFromInline
    func buildStages() -> [ScheduledStage] { // TODO: Allow API users to enforce order of certain systems.
        var remaining = systems
        var stages: [ScheduledStage] = []

        while !remaining.isEmpty {
            var stage: [System] = []
            stage.reserveCapacity(remaining.count)
            var stageResourceReaders = Set<ResourceKey>()
            var stageResourceWriters = Set<ResourceKey>()
            var stageComponentReaders = ComponentSignature()
            var stageComponentWriters = ComponentSignature()

            // Try to pack as many systems as possible into this stage
            var i = 0
            while i < remaining.count {
                let system = remaining[i]
                let accesses = system.metadata.resourceAccess
                var systemResourceReaders = Set<ResourceKey>()
                var systemResourceWriters = Set<ResourceKey>()
                let systemComponentReaders = system.metadata.readSignature
                let systemComponentWriters = system.metadata.writeSignature

                for (key, access) in accesses {
                    switch access {
                    case .read:  systemResourceReaders.insert(key)
                    case .write: systemResourceWriters.insert(key)
                    }
                }

                // Conflict rules:
                // - A writer conflicts with any existing reader/writer of same resource
                // - A reader conflicts with existing writer of same resource
                let writeResourceConflict = !systemResourceWriters.isDisjoint(with: stageResourceReaders.union(stageResourceWriters))
                let readResourceConflict  = !systemResourceReaders.isDisjoint(with: stageResourceWriters)
                let writeComponentConflict = !systemComponentWriters.isDisjoint(with: stageComponentReaders.union(stageComponentWriters))
                let readComponentConflict  = !systemComponentReaders.isDisjoint(with: stageComponentWriters)

                if writeResourceConflict || readResourceConflict || writeComponentConflict || readComponentConflict {
                    i += 1
                    continue
                } else {
                    stage.append(system)
                    stageResourceReaders.formUnion(systemResourceReaders)
                    stageResourceWriters.formUnion(systemResourceWriters)
                    stageComponentReaders.formUnion(systemComponentReaders)
                    stageComponentWriters.formUnion(systemComponentWriters)
                    remaining.remove(at: i)
                }
            }

            // Fallback: if nothing fit (shouldn’t happen), force schedule first remaining
            if stage.isEmpty, let first = remaining.first {
                stage = [first]
                remaining.removeFirst()
            }

            stages.append(ScheduledStage(systems: stage))
        }

        return stages
    }
}
