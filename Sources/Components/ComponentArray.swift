// TODO: This was made so that we don't cast every single component but rather the whole array once. But it seems this didn't have any effect?
//       Maybe there are just some other problems which just prevent this optimization from being utilized. Maybe first fix the QueryTransit stuff.
protocol AnyComponentArrayBox {
    mutating func remove(id: Entity.ID) -> Void
    mutating func append(_: any Component, id: Entity.ID) -> Void
    func get(_: Entity.ID) -> any Component
    mutating func `set`(_: Entity.ID, newValue: any Component) -> Void
    func entityIDsInStorageOrder() -> [Entity.ID]
}

//extension ComponentArray: AnyComponentArrayBox {
//    mutating func remove(id: Entity.ID) -> Void {
//        self.remove(id)
//    }
//
//    mutating func append(_ component: any Components.Component, id: Entity.ID) -> Void {
//        self.append(component as! Component, to: id)
//    }
//
//    func get(_ id: Entity.ID) -> any Components.Component {
//        self[id]
//    }
//
//    mutating func `set`(_ id: Entity.ID, newValue: any Components.Component) -> Void {
//        self[id] = newValue as! Component
//    }
//
//    func `as`<C: Components.Component>(_: C.Type) -> ComponentArray<C> {
//        guard C.self == Component.self else { fatalError("Mismatching type.") }
//        return self as! ComponentArray<C>
//    }
//}

final class ComponentArrayBox<C: Component>: AnyComponentArrayBox {
    var base: ComponentArray<C>

    init(_ base: ComponentArray<C>) {
        self.base = base
    }

    func remove(id: Entity.ID) -> Void {
        base.remove(id)
    }

    func append(_ component: any Component, id: Entity.ID) -> Void {
        base.append(component as! C, to: id)
    }

    func get(_ id: Entity.ID) -> any Component {
        base[id]
    }

    func `set`(_ id: Entity.ID, newValue: any Component) -> Void {
        base[id] = newValue as! C
    }

    func entityIDsInStorageOrder() -> [Entity.ID] {
        base.entityIDsInStorageOrder()
    }
}

struct AnyComponentArray {
    private var base: any AnyComponentArrayBox

    init<C: Component>(_ base: ComponentArray<C>) {
        self.base = ComponentArrayBox(base)
    }

    mutating func remove(_ entityID: Entity.ID) {
        base.remove(id: entityID)
    }

    mutating func append(_ component: any Component, id: Entity.ID) -> Void {
        base.append(component, id: id)
    }

    subscript(entityID entityID: Entity.ID) -> any Component {
        _read {
            yield base.get(entityID)
        }
        mutating set {
            base.set(entityID, newValue: newValue)
        }
    }

    func entityIDsInStorageOrder() -> [Entity.ID] {
        base.entityIDsInStorageOrder()
    }

    func withBuffer<C: Component, Result>(_ of: C.Type, _ body: (UnsafeMutableBufferPointer<C>) throws -> Result) rethrows -> Result {
        let typed = base as! ComponentArrayBox<C>
        return try typed.base.withUnsafeMutableBufferPointer { buf in
             try body(buf)
        }
    }
}

struct ComponentArray<Component: Components.Component>: Collection {
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

    @inlinable
    @inline(__always)
    mutating func withUnsafeMutableBufferPointer<R>(_ body: (inout UnsafeMutableBufferPointer<Element>) throws -> R) rethrows -> R {
        try components.withUnsafeMutableBufferPointer(body)
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
        _read {
            guard let index = entityToComponents[entityID] else {
                fatalError("Entity does not exist.")
            }
            yield components[index]
        }
        _modify {
            guard let index = entityToComponents[entityID] else {
                fatalError("Entity does not exist.")
            }
            yield &components[index]
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
