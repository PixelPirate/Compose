// TODO: Make ComponentArray a proper SparseSet, this should improve entity membership performance
//       Especially when querying one entity for many entities, a sparse set should be best (why?)
// TODO: When I have sparse sets, then I guess I could add EnTT groups on top?
// TODO: Do I want archetypes? If yes, I definitely want the option to store specific components as spare sets.
// TODO: Do I want all three? Archetypes and SparseSets and then a group option for the sparse set components?
//       E.g. one could say Transform, Mesh and Material are all sparse and then also make a group for these three.
//       Then other general purpose components just get the archetype magic and some flags just get a sparse set
//       without groups.
//       Sounds kind of cool.
// TODO: Parallelise queries. It should be memory safe since every entity has it's own memory location.
//       I don't think systems can be parallel though, right?

protocol AnyComponentArrayBox: AnyObject {
    func remove(id: Entity.ID) -> Void
    func append(_: any Component, id: Entity.ID) -> Void
    func get(_: Entity.ID) -> any Component
    func `set`(_: Entity.ID, newValue: any Component) -> Void
    var entityToComponents: [Entity.ID: Array.Index] { get }
}

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

    var entityToComponents: [Entity.ID: Array.Index] {
        _read {
            yield base.entityToComponents
        }
    }
}

public struct AnyComponentArray {
    private var base: any AnyComponentArrayBox

    public init<C: Component>(_ base: ComponentArray<C>) {
        self.base = ComponentArrayBox(base)
    }

    public mutating func remove(_ entityID: Entity.ID) {
        base.remove(id: entityID)
    }

    public mutating func append(_ component: any Component, id: Entity.ID) -> Void {
        base.append(component, id: id)
    }

    public subscript(entityID entityID: Entity.ID) -> any Component {
        _read {
            yield base.get(entityID)
        }
        mutating set {
            base.set(entityID, newValue: newValue)
        }
    }

    public var entityToComponents: [Entity.ID: Array.Index] {
        _read {
            yield base.entityToComponents
        }
    }

    public func withBuffer<C: Component, Result>(
        _ of: C.Type,
        _ body: (UnsafeMutableBufferPointer<C>, [Entity.ID : Array.Index]) throws -> Result
    ) rethrows -> Result {
        let typed = base as! ComponentArrayBox<C>
        let indices = typed.entityToComponents
        return try typed.base.withUnsafeMutableBufferPointer { buffer in
             try body(buffer, indices)
        }
    }
}

public struct ComponentArray<Component: Components.Component>: Collection {
    @usableFromInline
    internal var components: ContiguousArray<Component> = []
    private(set) var entityToComponents: [Entity.ID: Array.Index] = [:]
    private(set) var componentsToEntities: [Array.Index: Entity.ID] = [:]

    public init(_ pairs: (Entity.ID, Component)...) {
        for (id, component) in pairs {
            append(component, to: id)
        }
    }

    public init(_ pairs: [(Entity.ID, Component)]) {
        for (id, component) in pairs {
            append(component, to: id)
        }
    }

    @inlinable
    @inline(__always)
    public mutating func withUnsafeMutableBufferPointer<R>(_ body: (inout UnsafeMutableBufferPointer<Element>) throws -> R) rethrows -> R {
        try components.withUnsafeMutableBufferPointer(body)
    }

    /// Returns true if this array contains a component for the given entity.
    public func containsEntity(_ entityID: Entity.ID) -> Bool {
        entityToComponents[entityID] != nil
    }

    public mutating func append(_ component: Component, to entityID: Entity.ID) {
        components.append(component)
        entityToComponents[entityID] = components.endIndex - 1
        componentsToEntities[components.endIndex - 1] = entityID
    }

    public mutating func remove(_ entityID: Entity.ID) {
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

    public subscript(_ entityID: Entity.ID) -> Component {
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

    public var startIndex: ContiguousArray.Index { components.startIndex }
    public var endIndex: ContiguousArray.Index { components.endIndex }

    public func index(after i: ContiguousArray.Index) -> ContiguousArray.Index {
        components.index(after: i)
    }

    public subscript(position: ContiguousArray.Index) -> Component {
        components[position]
    }
}
