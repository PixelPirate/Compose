public struct Coordinator {
    @usableFromInline
    var pool = ComponentPool()
    //var tables = ArchetypePool()
    var indices = IndexRegistry()
    var systemManager = SystemManager()

    @usableFromInline
    internal private(set) var entitySignatures: ContiguousArray<ComponentSignature> = [] // Indexed by SlotIndex

    @usableFromInline
    var signatureQueryCache: [QueryHash: SignatureQueryPlan] = [:]

    @usableFromInline
    var sparseQueryCache: [QueryHash: SparseQueryPlan] = [:]

    @usableFromInline
    private(set) var worldVersion: UInt64 = 0

    public init() {}

    @inlinable @inline(__always)
    public subscript(signatureFor slot: SlotIndex) -> ComponentSignature {
        _read {
            yield entitySignatures[slot.rawValue]
        }
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

    @discardableResult
    public mutating func spawn() -> Entity.ID {
        let newEntity = indices.allocateID()
        let signature = ComponentSignature()
        setSpawnedSignature(newEntity, signature: signature)
        // I could do this and not do the check in the Query. Trades setup time with iteration time. But I couldn't really measure a difference.
//        pool.ensureSparseSetCount(includes: newEntity)
        return newEntity
    }

    mutating private func setSpawnedSignature(_ entityID: Entity.ID, signature: ComponentSignature) {
        if entitySignatures.endIndex == entityID.slot.rawValue {
            entitySignatures.append(signature)
        } else {
            // This is the only place where new entities get added, so it can't happen that
            // more than 1 signature is missing.
            entitySignatures[entityID.slot.rawValue] = signature
        }
    }

    public mutating func add<C: Component>(_ component: C, to entityID: Entity.ID) {
        defer {
            worldVersion += 1
        }
        pool.append(component, for: entityID)
        let newSignature = entitySignatures[entityID.slot.rawValue].appending(C.componentTag)
        entitySignatures[entityID.slot.rawValue] = newSignature
//        systemManager.updateSignature(newSignature, for: entityID) // TODO: Do I need that?
    }

    public mutating func remove(_ componentTag: ComponentTag, from entityID: Entity.ID) {
        defer {
            worldVersion += 1
        }
        pool.remove(componentTag, entityID)
        let newSignature = entitySignatures[entityID.slot.rawValue].removing(componentTag)
        entitySignatures[entityID.slot.rawValue] = newSignature
//        systemManager.updateSignature(newSignature, for: entityID) // TODO: Do I need that?
    }

    public mutating func remove<C: Component>(_ componentType: C.Type = C.self, from entityID: Entity.ID) {
        defer {
            worldVersion += 1
        }
        pool.remove(componentType, entityID)
        let newSignature = entitySignatures[entityID.slot.rawValue].removing(C.componentTag)
        entitySignatures[entityID.slot.rawValue] = newSignature
    }

    public mutating func destroy(_ entityID: Entity.ID) {
        defer {
            worldVersion += 1
        }
        indices.free(id: entityID)
        pool.remove(entityID)
        systemManager.remove(entityID)
        entitySignatures[entityID.slot.rawValue] = ComponentSignature()
    }

    public mutating func add(_ system: some System) {
        systemManager.add(system)
    }

    public mutating func remove(_ systemID: SystemID) {
        systemManager.remove(systemID)
    }

    public mutating func updateSystemSignature(_ signature: ComponentSignature, systemID: SystemID) {
        systemManager.setSignature(signature, systemID: systemID)
    }

    public func run() {
        // system, schedule?
    }
}
