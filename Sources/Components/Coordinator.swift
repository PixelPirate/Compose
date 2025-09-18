struct Coordinator {
    private var systemManager = SystemManager()
    private var componentPool = ComponentPool()

//    mutating func remove(_ enitity: Entity) {
//        systemManager.remove(enitity)
//        componentPool.remove(enitity.id)
//    }

    mutating func addComponent<C: Component>(_ component: C, to entity: inout Entity) {
        componentPool.append(component, for: entity.id)
        entity.signature.rawHashValue.insert(C.componentTag.rawValue)
        systemManager.updateSignature(entity.signature, for: entity.id)
    }

    mutating func removeComponent<C: Component>(_ componentType: C.Type = C.self, from entity: inout Entity) {
        componentPool.remove(componentType, entity.id)
        entity.signature.rawHashValue.remove(C.componentTag.rawValue)
        systemManager.updateSignature(entity.signature, for: entity.id)
    }

    subscript<C: Component>(_ componentType: C.Type = C.self, entityID: Entity.ID) -> C {
        componentPool[componentType, entityID]
    }

    mutating func add(_ system: some System) {
        systemManager.add(system)
    }

    mutating func updateSystemSignature(_ signature: ComponentSignature, systemID: SystemID) {
        systemManager.setSignature(signature, systemID: systemID)
    }
}

struct Coordinator2 {
    var pool = ComponentPool()
    //var tables = ArchetypePool()
    var indices = IndexRegistry()
    var systemManager = SystemManager()

    private var nextEntityID: Entity.ID.Index = 1

    @discardableResult
    mutating func spawn<each C: Component>(_ components: repeat each C) -> Entity {
        let newEntity = Entity.ID(rawValue: nextEntityID)
        nextEntityID += 1
        for component in repeat each components {
            pool.append(component, for: newEntity)
        }

        return Entity(
            id: newEntity,
            signature: ComponentSignature() // TODO: (repeat (each C).componentTag)
        )
    }

    mutating func add(_ component: some Component, to entityID: Entity.ID) {
        pool.append(component, for: entityID)
        entity.signature.rawHashValue.insert(C.componentTag.rawValue)
        systemManager.updateSignature(entity.signature, for: entity.id)    }

    mutating func remove(_ componentTag: ComponentTag, from entityID: Entity.ID) {
        pool.remove(componentTag, entityID)
    }

    mutating func remove<C: Component>(_ componentType: C.Type = C.self, from entityID: Entity.ID) {
        pool.remove(componentType, entityID)
    }

    mutating func destroy(_ entityID: Entity.ID) {
        pool.remove(entityID)
        systemManager.remove(entityID)
    }

    mutating func perform<each T: Component>(_ query: Query<repeat each T>, _ handler: (repeat (each T).ResolvedType) -> Void) {
        query(&self, handler)
    }

    func run() {
        // system, schedule?
    }
}
