struct Coordinator {
    private var systemManager = SystemManager()
    private var componentPool = ComponentPool()

    mutating func remove(_ enitity: Entity) {
        systemManager.remove(enitity)
        componentPool.remove(enitity.id)
    }

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

    mutating func modify<C: Component>(_ componentType: C.Type = C.self, _ entityID: Entity.ID, map: (inout C) -> Void) {
        componentPool.modify(componentType, entityID, map: map)
    }
}
