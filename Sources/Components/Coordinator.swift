import Synchronization
import Foundation
import os

@usableFromInline
struct ComponentChangeRecord {
    @usableFromInline
    var added: [SlotIndex: UInt64] = [:]

    @usableFromInline
    var changed: [SlotIndex: UInt64] = [:]

    @usableFromInline
    init(added: [SlotIndex : UInt64] = [:], changed: [SlotIndex : UInt64] = [:]) {
        self.added = added
        self.changed = changed
    }

    @usableFromInline @inline(__always)
    mutating func markAdded(slot: SlotIndex, tick: UInt64) {
        added[slot] = tick
        changed[slot] = tick
    }

    @usableFromInline @inline(__always)
    mutating func markChanged(slot: SlotIndex, tick: UInt64) {
        changed[slot] = tick
    }

    @usableFromInline @inline(__always)
    mutating func remove(slot: SlotIndex) {
        added.removeValue(forKey: slot)
        changed.removeValue(forKey: slot)
    }

    @usableFromInline @inline(__always)
    var isEmpty: Bool {
        added.isEmpty && changed.isEmpty
    }
}

public struct ResourceKey: Hashable, Sendable {
    @usableFromInline
    let type: ObjectIdentifier

    @inlinable @inline(__always)
    public init<T>(_ type: T.Type) {
        self.type = ObjectIdentifier(type)
    }

    @inlinable @inline(__always)
    public init(_ identifier: ObjectIdentifier) {
        self.type = identifier
    }
}

public final class Coordinator {
    @usableFromInline
    var pool = ComponentPool()

    @usableFromInline
    var indices = IndexRegistry()

    @usableFromInline
    var systemManager = SystemManager()

    @usableFromInline
    internal private(set) var entitySignatures: ContiguousArray<ComponentSignature> = [] // Indexed by SlotIndex

    @usableFromInline
    var changeTick: UInt64 = 0

    @usableFromInline
    var componentChangeRecords: [ComponentTag: ComponentChangeRecord] = [:]

    @usableFromInline
    let changeObservationLock = OSAllocatedUnfairLock()

    @usableFromInline
    var systemLastRunChangeTick: [SystemID: UInt64] = [:]

    @usableFromInline
    let systemTickLock = OSAllocatedUnfairLock()

    @usableFromInline
    var eventManager = EventManager()

    @usableFromInline
    var signatureQueryCache: [QueryHash: SignatureQueryPlan] = [:]
    @usableFromInline
    internal let signatureQueryCacheLock = OSAllocatedUnfairLock() // TODO: Instead of these locks: Explore atomic pointer swap.

    @usableFromInline
    var sparseQueryCache: [QueryHash: SparseQueryPlan] = [:]
    @usableFromInline
    internal let sparseQueryCacheLock = OSAllocatedUnfairLock()

    @usableFromInline
    var slotsQueryCache: [QueryHash: SlotsQueryPlan] = [:]
    @usableFromInline
    internal let slotsQueryCacheLock = OSAllocatedUnfairLock()

    @usableFromInline
    var groups = Groups()

    @usableFromInline
    var knownGroupsMeta: [GroupSignature: GroupMetadata] = [:]

    @usableFromInline
    private(set) var worldVersion: UInt64 = 0

    @usableFromInline
    struct ResourceEntry {
        @usableFromInline
        var value: Any
        @usableFromInline
        var version: UInt64

        @usableFromInline
        init(value: Any, version: UInt64) {
            self.value = value
            self.version = version
        }
    }

    @usableFromInline
    internal private(set) var resources: [ResourceKey: ResourceEntry] = [:] // TODO: I don't think the mutex is needed. The executors already guarantee that a system has unique mutable access.
    @usableFromInline
    internal let resourcesLock = OSAllocatedUnfairLock()

    @usableFromInline
    private(set) var resourceClock: UInt64 = 0

    public init() {
        MainSystem.install(into: self)
    }

    @inlinable @inline(__always)
    public subscript(signatureFor slot: SlotIndex) -> ComponentSignature {
        _read {
            yield entitySignatures[slot.rawValue]
        }
    }

    @inlinable @inline(__always)
    func makeEntityID(for slot: SlotIndex) -> Entity.ID {
        Entity.ID(slot: slot, generation: indices[generationFor: slot])
    }

    @inlinable @inline(__always)
    public var liveEntities: [Entity.ID] {
        _read {
            yield indices.liveEntities
        }
    }

    @inlinable @inline(__always)
    func markComponentAdded(_ tag: ComponentTag, slot: SlotIndex) {
        changeObservationLock.lock()
        defer { changeObservationLock.unlock() }
        changeTick &+= 1
        var record = componentChangeRecords[tag] ?? ComponentChangeRecord()
        record.markAdded(slot: slot, tick: changeTick)
        componentChangeRecords[tag] = record
    }

    @inlinable @inline(__always)
    func markComponentMutated(_ tag: ComponentTag, slot: SlotIndex) {
        changeObservationLock.lock()
        defer { changeObservationLock.unlock() }
        changeTick &+= 1
        var record = componentChangeRecords[tag] ?? ComponentChangeRecord()
        record.markChanged(slot: slot, tick: changeTick)
        componentChangeRecords[tag] = record
    }

    @inlinable @inline(__always)
    func clearComponentChanges(_ tag: ComponentTag, slot: SlotIndex) {
        changeObservationLock.lock()
        defer { changeObservationLock.unlock() }
        guard var record = componentChangeRecords[tag] else { return }
        record.remove(slot: slot)
        if record.isEmpty {
            componentChangeRecords.removeValue(forKey: tag)
        } else {
            componentChangeRecords[tag] = record
        }
    }

    @inlinable @inline(__always)
    func componentAdded(_ tag: ComponentTag, slot: SlotIndex, since tick: UInt64) -> Bool {
        changeObservationLock.lock()
        defer { changeObservationLock.unlock() }
        guard let record = componentChangeRecords[tag], let addedTick = record.added[slot] else {
            return false
        }
        return addedTick > tick
    }

    @inlinable @inline(__always)
    func componentChanged(_ tag: ComponentTag, slot: SlotIndex, since tick: UInt64) -> Bool {
        changeObservationLock.lock()
        defer { changeObservationLock.unlock() }
        guard let record = componentChangeRecords[tag], let changedTick = record.changed[slot] else {
            return false
        }
        return changedTick > tick
    }

    @inlinable @inline(__always)
    func currentChangeTickValue() -> UInt64 {
        changeObservationLock.lock()
        defer { changeObservationLock.unlock() }
        return changeTick
    }

    @inlinable @inline(__always)
    func lastRunChangeTick(for systemID: SystemID) -> UInt64 {
        systemTickLock.lock()
        defer { systemTickLock.unlock() }
        return systemLastRunChangeTick[systemID] ?? 0
    }

    @inlinable @inline(__always)
    func updateLastRunChangeTick(for systemID: SystemID, to tick: UInt64) {
        systemTickLock.lock()
        systemLastRunChangeTick[systemID] = tick
        systemTickLock.unlock()
    }

    @inlinable @inline(__always)
    func makeSystemQueryContext(for systemID: SystemID) -> QueryContext {
        QueryContext(
            coordinator: self,
            systemID: systemID,
            lastRunTick: lastRunChangeTick(for: systemID)
        )
    }

    @inlinable @inline(__always)
    @discardableResult
    public func spawn<each C: Component>(_ components: repeat each C) -> Entity.ID {
        defer {
            worldVersion &+= 1
        }
        let newEntity = indices.allocateID()

        var signature = ComponentSignature()
        for tag in repeat (each C).componentTag {
            signature.append(tag)
        }
        setSpawnedSignature(newEntity, signature: signature)

        // I could do this and not do the check in the Query. Trades setup time with iteration time. But I couldn't really measure a difference.
        pool.ensureSparseSetCount(includes: newEntity)

        for component in repeat each components {
            pool.append(component, for: newEntity)
            markComponentAdded(type(of: component).componentTag, slot: newEntity.slot)
            groups.onComponentAdded(type(of: component).componentTag, entity: newEntity, in: self)
        }

        return newEntity
    }

    @inlinable @inline(__always)
    public func isAlive(_ id: Entity.ID) -> Bool {
        indices[generationFor: id.slot] == id.generation
    }

    @inlinable @inline(__always)
    @discardableResult
    public func spawn() -> Entity.ID {
        let newEntity = indices.allocateID()
        let signature = ComponentSignature()
        setSpawnedSignature(newEntity, signature: signature)

        // I could do this and not do the check in the Query. Trades setup time with iteration time. But I couldn't really measure a difference.
        pool.ensureSparseSetCount(includes: newEntity)

        return newEntity
    }

    @usableFromInline
    internal func setSpawnedSignature(_ entityID: Entity.ID, signature: ComponentSignature) {
        if entitySignatures.endIndex == entityID.slot.rawValue {
            entitySignatures.append(signature)
        } else {
            // This is the only place where new entities get added, so it can't happen that
            // more than 1 signature is missing.
            entitySignatures[entityID.slot.rawValue] = signature
        }
    }

    @inlinable @inline(__always)
    public func add<C: Component>(_ component: C, to entityID: Entity.ID) {
        guard isAlive(entityID) else { return }
        defer {
            worldVersion &+= 1
        }
        pool.append(component, for: entityID)
        markComponentAdded(C.componentTag, slot: entityID.slot)
        let newSignature = entitySignatures[entityID.slot.rawValue].appending(C.componentTag)
        entitySignatures[entityID.slot.rawValue] = newSignature
        groups.onComponentAdded(C.componentTag, entity: entityID, in: self)
    }
    
    /// Add a new group.
    /// Group consist of 3 sets of components: Owned, included and excluded.
    /// Using the builder syntax you can specify these three roles like this:
    /// ```
    /// addGroup {
    ///     Transform.self // Owned
    ///     With<Material>.self // Included
    ///     Without<RigidBody>.self // Excluded
    /// }
    /// ```
    /// - Attention: Using virtual components (Like WithEntityID, Write, Optional) in a group definition is undefined behaviour and should be avoided.
    @inlinable @inline(__always) @discardableResult
    public func addGroup<each Owned: Component>(@QueryBuilder build: () -> BuiltQuery<repeat each Owned>) -> GroupSignature {
        let query = build().composite

        if query.writeSignature.isEmpty, query.readOnlySignature.isEmpty {
            let group = NonOwningGroup(
                required: Set(query.signature.tags), // Required = write ∪ readOnly ∪ backstage
                excluded: query.excludedComponents
            )
            groups.add(group, in: self)
            let signature = GroupSignature(query.querySignature)
            let meta = GroupMetadata(
                owned: ComponentSignature(),
                backstage: query.backstageSignature,
                excluded: query.excludedSignature
            )
            knownGroupsMeta[signature] = meta
            return signature
        } else {
            let group = Group(query: query)
            groups.add(group, in: self)
            let signature = GroupSignature(query.querySignature)
            let meta = GroupMetadata(
                owned: group.owned,
                backstage: group.backstageSignature,
                excluded: group.excludeSignature
            )
            knownGroupsMeta[signature] = meta
            return signature
        }
    }

    @inlinable @inline(__always)
    public func groupSize<each Owned: Component>(@QueryBuilder query: () -> BuiltQuery<repeat each Owned>) -> Int? {
        groups.groupSize(GroupSignature(query().composite.querySignature))
    }

    @inlinable @inline(__always)
    public func groupSize(_ signature: GroupSignature) -> Int? {
        groups.groupSize(signature)
    }

    @inlinable @inline(__always)
    public func groupSlots(_ signature: GroupSignature) -> ArraySlice<SlotIndex>? {
        groups.groupSlots(signature, in: &pool)
    }

    @inlinable @inline(__always)
    public func groupSlotsWithOwned(_ signature: GroupSignature) -> (ArraySlice<SlotIndex>, ComponentSignature)? {
        groups.groupSlotsWithOwned(signature, in: &pool)
    }

    @inlinable @inline(__always)
    public func isOwningGroup(_ signature: GroupSignature) -> Bool {
        groups.isOwning(signature)
    }

    public struct BestGroupResult {
        @inlinable @inline(__always)
        public init(slots: ArraySlice<SlotIndex>, exact: Bool, owned: ComponentSignature) {
            self.slots = slots
            self.exact = exact
            self.owned = owned
        }
        public let slots: ArraySlice<SlotIndex>
        public let exact: Bool
        public let owned: ComponentSignature
    }

    @inlinable @inline(__always)
    public func bestGroup(for query: QuerySignature) -> BestGroupResult? {
        let queryContained = query.write.union(query.readOnly).union(query.backstage)
        let accessed = query.write + query.readOnly
        let queryExcluded = query.excluded
        // Exact fast path
        if let (slots, owned) = groupSlotsWithOwned(GroupSignature(contained: queryContained, excluded: queryExcluded)) {
            return BestGroupResult(slots: slots, exact: true, owned: owned)
        }
        // Scan known groups for reusable candidates and score by owned overlap
        var best: (slots: ArraySlice<SlotIndex>, score: Int, size: Int, primaryRaw: Int, owned: ComponentSignature)? = nil
        for (sig, meta) in knownGroupsMeta {
            if !meta.contained.isSubset(of: queryContained) { continue }
            if !meta.excluded.isSubset(of: queryExcluded) { continue }
            guard let slots = groupSlots(sig) else { continue }
            // Score by owned ∩ accessed
            var score = 0
            let it = accessed.tags
            while let tag = it.next() {
                if meta.owned.contains(tag) { score &+= 1 }
            }
            // Tie-breaker 1: prefer smaller current packed size to reduce extra per-entity checks when not exact
            let ps = groups.primaryAndSize(sig)?.size ?? Int.max
            // Tie-breaker 2: deterministic: prefer lower primary tag rawValue
            let pr = groups.primaryAndSize(sig)?.primary.rawValue ?? Int.max

            if let current = best {
                if score > current.score ||
                   (score == current.score && ps < current.size) ||
                   (score == current.score && ps == current.size && pr < current.primaryRaw) {
                    best = (slots, score, ps, pr, meta.owned)
                }
            } else {
                best = (slots, score, ps, pr, meta.owned)
            }
        }
        if let b = best { return BestGroupResult(slots: b.slots, exact: false, owned: b.owned) }
        return nil
    }

    @inlinable @inline(__always)
    public func removeGroup<each Owned: Component>(@QueryBuilder query: () -> BuiltQuery<repeat each Owned>) {
        let built = query().composite
        let signature = GroupSignature(built.querySignature)
        groups.remove(built.querySignature)
        knownGroupsMeta.removeValue(forKey: signature)
    }

    @inlinable @inline(__always)
    public func remove(_ componentTag: ComponentTag, from entityID: Entity.ID) {
        guard isAlive(entityID) else { return }
        defer {
            worldVersion &+= 1
        }
        groups.onWillRemoveComponent(componentTag, entity: entityID, in: self)
        pool.remove(componentTag, entityID)
        clearComponentChanges(componentTag, slot: entityID.slot)
        let newSignature = entitySignatures[entityID.slot.rawValue].removing(componentTag)
        entitySignatures[entityID.slot.rawValue] = newSignature
    }

    @inlinable @inline(__always)
    public func remove<C: Component>(_ componentType: C.Type = C.self, from entityID: Entity.ID) {
        guard isAlive(entityID) else { return }
        defer {
            worldVersion &+= 1
        }
        groups.onWillRemoveComponent(C.componentTag, entity: entityID, in: self)
        pool.remove(componentType, entityID)
        clearComponentChanges(C.componentTag, slot: entityID.slot)
        let newSignature = entitySignatures[entityID.slot.rawValue].removing(C.componentTag)
        entitySignatures[entityID.slot.rawValue] = newSignature
    }

    @inlinable @inline(__always)
    public func destroy(_ entityID: Entity.ID) {
        guard isAlive(entityID) else { return }
        defer {
            worldVersion &+= 1
        }
        indices.free(id: entityID)
        for componentTag in self[signatureFor: entityID.slot].tags {
            groups.onWillRemoveComponent(componentTag, entity: entityID, in: self)
            clearComponentChanges(componentTag, slot: entityID.slot)
        }
        pool.remove(entityID)
        entitySignatures[entityID.slot.rawValue] = ComponentSignature()
    }

    @inlinable @inline(__always)
    public func add(_ system: some System) {
        systemManager.add(system)
    }

    @inlinable @inline(__always)
    public func remove(_ systemID: SystemID) {
        systemManager.remove(systemID)
    }

    @inlinable @inline(__always)
    public func addResource<R>(_ resource: sending R) {
        resourcesLock.lock()
        defer { resourcesLock.unlock() }
        resourceClock &+= 1
        resources[ResourceKey(R.self)] = ResourceEntry(value: resource, version: resourceClock)
    }

    @inlinable @inline(__always)
    public func resource<R>(_ type: R.Type = R.self) -> R {
        resourcesLock.lock()
        defer { resourcesLock.unlock() }
        return resources[ResourceKey(R.self)]!.value as! R
    }

    @inlinable @inline(__always)
    public subscript<R>(resource resourceType: sending R.Type = R.self) -> R {
        @inlinable @inline(__always)
        get {
            resourcesLock.lock()
            defer { resourcesLock.unlock() }
            return resources[ResourceKey(R.self)]!.value as! R
        }
        @inlinable @inline(__always)
        set {
            resourcesLock.lock()
            resourceClock &+= 1
            resources[ResourceKey(R.self)] = ResourceEntry(value: newValue, version: resourceClock)
            resourcesLock.unlock()
        }
    }

    public struct ResourceVersionSnapshot: Sendable {
        @usableFromInline
        let versions: [ResourceKey: UInt64]

        @inlinable @inline(__always)
        init(versions: [ResourceKey: UInt64]) {
            self.versions = versions
        }
    }

    @inlinable @inline(__always)
    public func resourceVersion<R>(_ type: R.Type = R.self) -> UInt64? {
        resourcesLock.lock()
        defer { resourcesLock.unlock() }
        let key = ResourceKey(R.self)
        return resources[key]?.version
    }

    @inlinable @inline(__always)
    public func makeResourceVersionSnapshot() -> ResourceVersionSnapshot {
        resourcesLock.lock()
        defer { resourcesLock.unlock() }
        let versions = resources.mapValues(\.version)
        return ResourceVersionSnapshot(versions: versions)
    }

    @inlinable @inline(__always)
    public func updatedResources(since snapshot: ResourceVersionSnapshot) -> [ResourceKey] {
        resourcesLock.lock()
        defer { resourcesLock.unlock() }

        var updated: [ResourceKey] = []
        updated.reserveCapacity(resources.count)

        for (key, entry) in resources {
            guard let previous = snapshot.versions[key] else {
                updated.append(key)
                continue
            }

            if previous != entry.version {
                updated.append(key)
            }
        }

        return updated
    }

    @inlinable @inline(__always)
    public func resourceIfUpdated<R>(_ type: R.Type = R.self, since snapshot: ResourceVersionSnapshot) -> R? {
        resourcesLock.lock()
        defer { resourcesLock.unlock() }

        let key = ResourceKey(R.self)

        guard let entry = resources[key] else {
            return nil
        }

        guard snapshot.versions[key] == entry.version else {
            return (entry.value as! R)
        }

        return nil
    }

    @inlinable @inline(__always)
    public func resourceUpdated<R>(_ type: R.Type = R.self, since snapshot: ResourceVersionSnapshot) -> Bool {
        resourcesLock.lock()
        defer { resourcesLock.unlock() }

        let key = ResourceKey(R.self)

        guard let entry = resources[key] else {
            return false
        }

        return snapshot.versions[key] != entry.version
    }

    @inlinable @inline(__always)
    public func addSchedule(_ schedule: Schedule) {
        systemManager.addSchedule(schedule)
    }

    @inlinable @inline(__always)
    public func addSystem(_ label: ScheduleLabel, system: some System) {
        systemManager.addSystem(label, system: system)
    }

    @inlinable @inline(__always)
    public func runSchedule(_ scheduleLabel: ScheduleLabel) {
        systemManager.schedules[scheduleLabel]?.run(self)
    }

    @inlinable @inline(__always)
    public func run() {
        runSchedule(.main)
    }

    @inlinable @inline(__always)
    public func update(_ scheduleLabel: ScheduleLabel, update: (inout Schedule) -> Void) {
        systemManager.update(scheduleLabel, update: update)
    }

    @inlinable @inline(__always)
    func eventWriter<E: Event>(_ type: E.Type = E.self) -> EventWriter<E> {
        eventManager.writer(type)
    }

    @inlinable @inline(__always)
    func sendEvent<E: Event>(_ event: E) {
        eventManager.send(event)
    }

    @inlinable @inline(__always)
    func readEvents<E: Event>(_ type: E.Type = E.self, state: inout EventReaderState<E>) -> EventSequence<E> {
        eventManager.read(type, state: &state)
    }

    @inlinable @inline(__always)
    func drainEvents<E: Event>(_ type: E.Type = E.self) -> [E] {
        eventManager.drain(type)
    }
}
