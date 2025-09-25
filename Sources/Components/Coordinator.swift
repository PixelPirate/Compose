public struct Coordinator {
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
    var sparseQueryCache: [QueryHash: SparseQueryPlan] = [:]

    @usableFromInline
    private(set) var worldVersion: UInt64 = 0

    @usableFromInline
    private(set) var resources: [ObjectIdentifier: Any] = [:]

    @inlinable @inline(__always)
    public init() {}

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

    @discardableResult
    public mutating func spawn<each C: Component>(_ components: repeat each C) -> Entity.ID {
        defer {
            worldVersion += 1
        }
        let newEntity = indices.allocateID()
        for component in repeat each components {
            pool.append(component, for: newEntity)
        }
        // I could do this and not do the check in the Query. Trades setup time with iteration time. But I couldn't really measure a difference.
//        pool.ensureSparseSetCount(includes: newEntity)

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
    public mutating func spawn() -> Entity.ID {
        let newEntity = indices.allocateID()
        let signature = ComponentSignature()
        setSpawnedSignature(newEntity, signature: signature)
        // I could do this and not do the check in the Query. Trades setup time with iteration time. But I couldn't really measure a difference.
//        pool.ensureSparseSetCount(includes: newEntity)
        return newEntity
    }

    @usableFromInline
    mutating internal func setSpawnedSignature(_ entityID: Entity.ID, signature: ComponentSignature) {
        if entitySignatures.endIndex == entityID.slot.rawValue {
            entitySignatures.append(signature)
        } else {
            // This is the only place where new entities get added, so it can't happen that
            // more than 1 signature is missing.
            entitySignatures[entityID.slot.rawValue] = signature
        }
    }

    @inlinable @inline(__always)
    public mutating func add<C: Component>(_ component: C, to entityID: Entity.ID) {
        guard isAlive(entityID) else { return }
        defer {
            worldVersion += 1
        }
        pool.append(component, for: entityID)
        let newSignature = entitySignatures[entityID.slot.rawValue].appending(C.componentTag)
        entitySignatures[entityID.slot.rawValue] = newSignature
    }

    @inlinable @inline(__always)
    public mutating func remove(_ componentTag: ComponentTag, from entityID: Entity.ID) {
        guard isAlive(entityID) else { return }
        defer {
            worldVersion += 1
        }
        pool.remove(componentTag, entityID)
        let newSignature = entitySignatures[entityID.slot.rawValue].removing(componentTag)
        entitySignatures[entityID.slot.rawValue] = newSignature
    }

    @inlinable @inline(__always)
    public mutating func remove<C: Component>(_ componentType: C.Type = C.self, from entityID: Entity.ID) {
        guard isAlive(entityID) else { return }
        defer {
            worldVersion += 1
        }
        pool.remove(componentType, entityID)
        let newSignature = entitySignatures[entityID.slot.rawValue].removing(C.componentTag)
        entitySignatures[entityID.slot.rawValue] = newSignature
    }

    @inlinable @inline(__always)
    public mutating func destroy(_ entityID: Entity.ID) {
        guard isAlive(entityID) else { return }
        defer {
            worldVersion += 1
        }
        indices.free(id: entityID)
        pool.remove(entityID)
        entitySignatures[entityID.slot.rawValue] = ComponentSignature()
    }

    @inlinable @inline(__always)
    public mutating func add(_ system: some System) {
        systemManager.add(system)
    }

    @inlinable @inline(__always)
    public mutating func remove(_ systemID: SystemID) {
        systemManager.remove(systemID)
    }

    @inlinable @inline(__always)
    public mutating func addRessource<R>(_ ressource: R) {
        resources[ObjectIdentifier(R.self)] = ressource
    }

    @inlinable @inline(__always)
    public func resource<R>(_ type: R.Type = R.self) -> R {
        resources[ObjectIdentifier(R.self)] as! R
    }

    @inlinable @inline(__always)
    public mutating func addSchedule(_ schedule: Schedule) {
        systemManager.addSchedule(schedule)
    }

    @inlinable @inline(__always)
    public mutating func addSystem<S: ScheduleLabel>(_ s: S.Type = S.self, system: some System) {
        systemManager.addSystem(S.self, system: system)
    }

    @inlinable @inline(__always)
    public mutating func runSchedule<S: ScheduleLabel>(_ scheduleLabel: S.Type = S.self) {
        systemManager.schedules[S.key]?.run(&self)
    }

    @inlinable @inline(__always)
    public mutating func runSchedule(_ scheduleLabelKey: ScheduleLabelKey) {
        systemManager.schedules[scheduleLabelKey]?.run(&self)
    }

    @inlinable @inline(__always)
    public func run() {
        // system, schedule?
    }
}
