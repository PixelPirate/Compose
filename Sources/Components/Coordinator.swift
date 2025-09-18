public struct Coordinator {
    @usableFromInline
    var pool = ComponentPool()
    //var tables = ArchetypePool()
    var indices = IndexRegistry()
    var systemManager = SystemManager()

    private var nextEntityID: Entity.ID.Index = 1
    private var entitySignatures: [Entity.ID: ComponentSignature] = [:]

    public init() {}

    @discardableResult
    public mutating func spawn<each C: Component>(_ components: repeat each C) -> Entity.ID {
        let newEntity = Entity.ID(rawValue: nextEntityID)
        nextEntityID += 1
        for component in repeat each components {
            pool.append(component, for: newEntity)
        }

        var signature = ComponentSignature()
        for tag in repeat (each C).componentTag {
            signature.append(tag)
        }
        entitySignatures[newEntity] = signature // TODO: ComponentSignature(repeat (each C).componentTag)
        return newEntity
    }

    @discardableResult
    public mutating func spawn() -> Entity.ID {
        let newEntity = Entity.ID(rawValue: nextEntityID)
        nextEntityID += 1
        let signature = ComponentSignature()
        entitySignatures[newEntity] = signature
        return newEntity
    }

    public mutating func add<C: Component>(_ component: C, to entityID: Entity.ID) {
        pool.append(component, for: entityID)
        let newSignature = entitySignatures[entityID]!.appending(C.componentTag)
        entitySignatures[entityID] = newSignature
        systemManager.updateSignature(newSignature, for: entityID)
    }

    public mutating func remove(_ componentTag: ComponentTag, from entityID: Entity.ID) {
        pool.remove(componentTag, entityID)
        let newSignature = entitySignatures[entityID]!.removing(componentTag)
        entitySignatures[entityID] = newSignature
        systemManager.updateSignature(newSignature, for: entityID)
    }

    public mutating func remove<C: Component>(_ componentType: C.Type = C.self, from entityID: Entity.ID) {
        pool.remove(componentType, entityID)
    }

    public mutating func destroy(_ entityID: Entity.ID) {
        pool.remove(entityID)
        systemManager.remove(entityID)
        entitySignatures.removeValue(forKey: entityID)
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

    public mutating func perform<each T: Component>(_ query: Query<repeat each T>, _ handler: (repeat (each T).ResolvedType) -> Void) {
        query(&self, handler)
    }

    public func run() {
        // system, schedule?
    }
}
