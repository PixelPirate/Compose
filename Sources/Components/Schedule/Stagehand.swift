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
    func buildStages() -> [ScheduledStage] { // TODO: Cache stages as one single [any System] until systems change.
        // Work on a mutable list of unscheduled systems
        var unscheduled: [any System] = Array(systems)
        var scheduledIDs = Set<SystemID>()
        var stages: [ScheduledStage] = []

        while !unscheduled.isEmpty {
            // Build one stage at a time from systems whose dependencies are satisfied
            var stage: [System] = []
            stage.reserveCapacity(remaining.count)
            var stageSystemIDs = Set<SystemID>()

            // Conflict tracking for this stage
            var stageResourceReaders = Set<ResourceKey>()
            var stageResourceWriters = Set<ResourceKey>()
            var stageComponentReaders = ComponentSignature()
            var stageComponentWriters = ComponentSignature()

            // We try to add as many as possible to this stage
            var progressed = true
            while progressed {
                progressed = false

                var i = 0
                while i < unscheduled.count {
                    let system = unscheduled[i]

                    // Only consider systems whose runAfter deps are already scheduled.
                    // Note: Dependencies must be in earlier stages; we do NOT allow a system
                    // to depend on something in the same stage, since stages run in parallel.
                    let deps = system.metadata.runAfter
                    let depsSatisfied = deps.isSubset(of: scheduledIDs)
                    if !depsSatisfied {
                        i += 1
                        continue
                    }

                    // Prepare per-system access sets
                    let accesses = system.metadata.resourceAccess
                    var systemResourceReaders = Set<ResourceKey>()
                    var systemResourceWriters = Set<ResourceKey>()
                    for (key, access) in accesses {
                        switch access {
                        case .read:  systemResourceReaders.insert(key)
                        case .write: systemResourceWriters.insert(key)
                        }
                    }
                    let systemComponentReaders = system.metadata.readSignature
                    let systemComponentWriters = system.metadata.writeSignature

                    // Conflict rules (unchanged):
                    // - A writer conflicts with any existing reader/writer of same resource
                    // - A reader conflicts with existing writer of same resource
                    let writeResourceConflict = !systemResourceWriters.isDisjoint(with: stageResourceReaders.union(stageResourceWriters))
                    let readResourceConflict  = !systemResourceReaders.isDisjoint(with: stageResourceWriters)
                    let writeComponentConflict = !systemComponentWriters.isDisjoint(with: stageComponentReaders.union(stageComponentWriters))
                    let readComponentConflict  = !systemComponentReaders.isDisjoint(with: stageComponentWriters)

                    if writeResourceConflict || readResourceConflict || writeComponentConflict || readComponentConflict {
                        // Can't place this system in the current stage; try next
                        i += 1
                        continue
                    }

                    // If no conflicts and deps satisfied, schedule it into this stage
                    stage.append(system)
                    stageSystemIDs.insert(system.metadata.id)
                    stageResourceReaders.formUnion(systemResourceReaders)
                    stageResourceWriters.formUnion(systemResourceWriters)
                    stageComponentReaders.formUnion(systemComponentReaders)
                    stageComponentWriters.formUnion(systemComponentWriters)

                    // Remove from unscheduled and mark progress
                    unscheduled.remove(at: i)
                    progressed = true
                    // Do not increment i; we removed the current element
                }
            }

            // If we couldn't add anything to this stage:
            if stage.isEmpty {
                // Either all remaining systems are blocked by dependencies (cycle),
                // or something unexpected happened. Detect a cycle in runAfter.
                let countBlockedByDeps = unscheduled.filter { !$0.metadata.runAfter.isSubset(of: scheduledIDs) }.count
                if countBlockedByDeps == unscheduled.count {
                    // All remaining systems are waiting on deps that will never resolve -> cycle.
                    let remainingIDs = unscheduled.map { $0.metadata.id }
                    preconditionFailure("Cyclic runAfter dependencies detected among systems: \(remainingIDs)")
                } else {
                    // There exist systems with deps satisfied, but none fit due to conflicts.
                    // Start a new stage by force-picking one with satisfied deps to make progress.
                    if let idx = unscheduled.firstIndex(where: { $0.metadata.runAfter.isSubset(of: scheduledIDs) }) {
                        let first = unscheduled.remove(at: idx)
                        stage = [first]
                    } else {
                        // Should not happen because countBlockedByDeps != unscheduled.count
                        let first = unscheduled.removeFirst()
                        stage = [first]
                    }
                }
            }

            // Finalize stage and mark its systems as scheduled
            for sys in stage {
                scheduledIDs.insert(sys.metadata.id)
            }
            stages.append(ScheduledStage(systems: stage))
        }

        return stages
    }
}
