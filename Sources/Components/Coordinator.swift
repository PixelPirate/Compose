import Synchronization
import Foundation
import os

public struct ResourceKey: Hashable {
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
    //var tables = ArchetypePool()

    @usableFromInline
    var indices = IndexRegistry()

    @usableFromInline
    var systemManager = SystemManager()

    @usableFromInline
    internal private(set) var entitySignatures: ContiguousArray<ComponentSignature> = [] // Indexed by SlotIndex

    @usableFromInline
    var signatureQueryCache: [QueryHash: SignatureQueryPlan] = [:]
    @usableFromInline
    internal let signatureQueryCacheLock = OSAllocatedUnfairLock()

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
    private(set) var worldVersion: UInt64 = 0

    @usableFromInline
    internal private(set) var resources: [ResourceKey: Any] = [:] // TODO: I don't think the mutex is needed. The executors already guarantee that a system has unique mutable access.
    @usableFromInline
    internal let resourcesLock = NSRecursiveLock()

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
    @discardableResult
    public func spawn<each C: Component>(_ components: repeat each C) -> Entity.ID {
        defer {
            worldVersion &+= 1
        }
        let newEntity = indices.allocateID()

        // I could do this and not do the check in the Query. Trades setup time with iteration time. But I couldn't really measure a difference.
        pool.ensureSparseSetCount(includes: newEntity)

        for component in repeat each components {
            pool.append(component, for: newEntity)
        }

        var signature = ComponentSignature()
        for tag in repeat (each C).componentTag {
            signature.append(tag)
        }
        setSpawnedSignature(newEntity, signature: signature)
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
        let newSignature = entitySignatures[entityID.slot.rawValue].appending(C.componentTag)
        entitySignatures[entityID.slot.rawValue] = newSignature
        groups.onComponentAdded(C.componentTag, entity: entityID, in: &pool)
    }

    @inlinable @inline(__always) @discardableResult
    public func addGroup<each Owned: Component>(@QueryBuilder build: () -> BuiltQuery<repeat each Owned>) -> GroupSignature {
        let query = build().composite
        groups.add(Group(query: query), in: &pool)
        return GroupSignature(query.querySignature)
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
    public func groupSlots(_ signature: GroupSignature) -> ContiguousArray<SlotIndex>? {
        groups.groupSlots(signature, in: &pool)
    }

    @inlinable @inline(__always)
    public func removeGroup<each Owned: Component>(@QueryBuilder query: () -> BuiltQuery<repeat each Owned>) {
        groups.remove(query().composite.querySignature)
    }

    @inlinable @inline(__always)
    public func remove(_ componentTag: ComponentTag, from entityID: Entity.ID) {
        guard isAlive(entityID) else { return }
        defer {
            worldVersion &+= 1
        }
        groups.onWillRemoveComponent(componentTag, entity: entityID, in: &pool)
        pool.remove(componentTag, entityID)
        let newSignature = entitySignatures[entityID.slot.rawValue].removing(componentTag)
        entitySignatures[entityID.slot.rawValue] = newSignature
    }

    @inlinable @inline(__always)
    public func remove<C: Component>(_ componentType: C.Type = C.self, from entityID: Entity.ID) {
        guard isAlive(entityID) else { return }
        defer {
            worldVersion &+= 1
        }
        groups.onWillRemoveComponent(C.componentTag, entity: entityID, in: &pool)
        pool.remove(componentType, entityID)
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
            groups.onWillRemoveComponent(componentTag, entity: entityID, in: &pool)
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
    public func addRessource<R>(_ resource: sending R) {
        resourcesLock.lock()
        defer { resourcesLock.unlock() }
        resources[ResourceKey(R.self)] = resource
    }

    @inlinable @inline(__always)
    public func resource<R>(_ type: R.Type = R.self) -> R {
        resourcesLock.lock()
        defer { resourcesLock.unlock() }
        return resources[ResourceKey(R.self)] as! R
    }

    @inlinable @inline(__always)
    public subscript<R>(resource resourceType: sending R.Type = R.self) -> R {
        @inlinable @inline(__always)
        _read {
            resourcesLock.lock()
            yield resources[ResourceKey(R.self)] as! R
            resourcesLock.unlock()
        }
        @inlinable @inline(__always)
        set {
            resourcesLock.lock()
            resources[ResourceKey(R.self)] = newValue
            resourcesLock.unlock()
        }
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
}
