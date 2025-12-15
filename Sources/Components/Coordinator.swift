import Synchronization
import Foundation
import os

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

@usableFromInline
struct ComponentSignaturesSpan {
    @usableFromInline
    let pointer: UnsafePointer<ComponentSignature>

    @inlinable @_transparent
    init(pointer: UnsafePointer<ComponentSignature>) {
        self.pointer = pointer
    }

    @inlinable @inline(__always)
    subscript(_ index: SlotIndex) -> ComponentSignature {
        @inlinable @_transparent
        unsafeAddress {
            pointer.advanced(by: index.rawValue)
        }
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
    private(set) var changeTick: UInt64 = 1

    @usableFromInline
    var systemChangeTicks: [SystemID: SystemTickRecord] = [:]

    @usableFromInline
    let systemChangeTickLock = OSAllocatedUnfairLock()

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

    @usableFromInline
    struct SystemTickRecord {
        @usableFromInline var lastRun: UInt64
        @usableFromInline var thisRun: UInt64
    }

    public struct SystemTickSnapshot: Sendable {
        public let lastRun: UInt64
        public let thisRun: UInt64

        @inlinable @inline(__always)
        init(lastRun: UInt64, thisRun: UInt64) {
            self.lastRun = lastRun
            self.thisRun = thisRun
        }

        @inline(__always)
        public static let never = SystemTickSnapshot(lastRun: .max, thisRun: .min)
    }

    @inlinable @inline(__always)
    public subscript(signatureFor slot: SlotIndex) -> ComponentSignature {
        _read {
            yield entitySignatures[slot.rawValue]
        }
    }

    @inlinable @inline(__always)
    var entitySignaturesView: ComponentSignaturesSpan {
        @inlinable @inline(__always)
        _read {
            yield ComponentSignaturesSpan(pointer: entitySignatures.withUnsafeBufferPointer { $0.baseAddress.unsafelyUnwrapped })
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

    @usableFromInline @inline(__always)
    func prepareSystemTickSnapshot(for systemID: SystemID) -> SystemTickSnapshot {
        systemChangeTickLock.lock()
        let record = systemChangeTicks[systemID] ?? SystemTickRecord(lastRun: 0, thisRun: 0)
        let snapshot = SystemTickSnapshot(lastRun: record.thisRun, thisRun: changeTick)
        systemChangeTicks[systemID] = SystemTickRecord(lastRun: record.thisRun, thisRun: changeTick)
        systemChangeTickLock.unlock()
        return snapshot
    }

    @usableFromInline @inline(__always)
    func advanceChangeTick() {
        changeTick &+= 1
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

        pool.ensureSparseSetCount(includes: newEntity)

        for component in repeat each components {
            pool.append(component, for: newEntity, changeTick: changeTick)
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
        defer {
            worldVersion &+= 1
        }
        let newEntity = indices.allocateID()
        let signature = ComponentSignature()
        setSpawnedSignature(newEntity, signature: signature)

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
        pool.append(component, for: entityID, changeTick: changeTick)
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
    public func groupSlots(_ signature: GroupSignature) -> ContiguousSpan<SlotIndex>? {
        groups.groupSlots(signature, in: &pool)
    }

    @inlinable @inline(__always)
    public func groupSlotsWithOwned(_ signature: GroupSignature) -> (ContiguousSpan<SlotIndex>, ComponentSignature)? {
        groups.groupSlotsWithOwned(signature, in: &pool)
    }

    @inlinable @inline(__always)
    public func isOwningGroup(_ signature: GroupSignature) -> Bool {
        groups.isOwning(signature)
    }

    public struct BestGroupResult {
        @inlinable @inline(__always)
        public init(slots: ContiguousSpan<SlotIndex>, exact: Bool, owned: ComponentSignature) {
            self.slots = slots
            self.exact = exact
            self.owned = owned
        }
        public let slots: ContiguousSpan<SlotIndex>
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
        var best: (slots: ContiguousSpan<SlotIndex>, score: Int, size: Int, primaryRaw: Int, owned: ComponentSignature)? = nil
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
        pool.remove(componentTag, entityID, changeTick: changeTick)
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
        pool.remove(componentType, entityID, changeTick: changeTick)
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
        }
        pool.remove(entityID)
        entitySignatures[entityID.slot.rawValue] = ComponentSignature()
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
    public func removeSystem(_ label: ScheduleLabel, systemID: SystemID) {
        systemManager.remove(systemID)
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
