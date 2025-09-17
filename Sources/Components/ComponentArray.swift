struct ComponentArray<Component>: Collection {
    private var components: ContiguousArray<Component> = []
    private var entityToComponents: [Entity.ID: Array.Index] = [:]
    private var componentsToEntities: [Array.Index: Entity.ID] = [:]

    init(_ pairs: (Entity.ID, Component)...) {
        for (id, component) in pairs {
            append(component, to: id)
        }
    }

    init(_ pairs: [(Entity.ID, Component)]) {
        for (id, component) in pairs {
            append(component, to: id)
        }
    }

    /// Returns the entity IDs in the same order as their components are stored.
    func entityIDsInStorageOrder() -> [Entity.ID] {
        var ids: [Entity.ID] = []
        ids.reserveCapacity(components.count)
        for idx in components.indices {
            guard let id = componentsToEntities[idx] else { fatalError("Missing entity mapping for component index.") }
            ids.append(id)
        }
        return ids
    }

    /// Returns true if this array contains a component for the given entity.
    func containsEntity(_ entityID: Entity.ID) -> Bool {
        entityToComponents[entityID] != nil
    }

    mutating func append(_ component: Component, to entityID: Entity.ID) {
        components.append(component)
        entityToComponents[entityID] = components.endIndex - 1
        componentsToEntities[components.endIndex - 1] = entityID
    }

    mutating func remove(_ entityID: Entity.ID) {
        guard let componentIndex = entityToComponents[entityID] else { return }
        guard componentIndex != components.endIndex - 1 else {
            componentsToEntities.removeValue(forKey: components.endIndex - 1)
            entityToComponents.removeValue(forKey: entityID)
            components.removeLast()
            return
        }

        guard let lastComponentEntity = componentsToEntities.removeValue(forKey: components.endIndex - 1) else {
            fatalError("Missing entity for last component.")
        }
        components[componentIndex] = components.removeLast()
        componentsToEntities[componentIndex] = lastComponentEntity
        entityToComponents[lastComponentEntity] = componentIndex
        entityToComponents.removeValue(forKey: entityID)
    }

    subscript(_ entityID: Entity.ID) -> Component {
        get {
            guard let index = entityToComponents[entityID] else {
                fatalError("Entity does not exist.")
            }
            return components[index]
        }
        set {
            guard let index = entityToComponents[entityID] else {
                fatalError("Entity does not exist.")
            }
            components[index] = newValue
        }
    }

    var startIndex: ContiguousArray.Index { components.startIndex }
    var endIndex: ContiguousArray.Index { components.endIndex }

    func index(after i: ContiguousArray.Index) -> ContiguousArray.Index {
        components.index(after: i)
    }

    subscript(position: ContiguousArray.Index) -> Component {
        components[position]
    }
}
