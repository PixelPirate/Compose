// TODO: When I have sparse sets, then I guess I could add EnTT groups on top?
// TODO: Do I want archetypes? If yes, I definitely want the option to store specific components as spare sets.
// TODO: Do I want all three? Archetypes and SparseSets and then a group option for the sparse set components?
//       E.g. one could say Transform, Mesh and Material are all sparse and then also make a group for these three.
//       Then other general purpose components just get the archetype magic and some flags just get a sparse set
//       without groups.
//       Sounds kind of cool.
// TODO: Parallelise queries. It should be memory safe since every entity has it's own memory location.
//       I don't think systems can be parallel though, right?

public protocol AnyComponentArrayBox: AnyObject {
    func remove(id: Entity.ID) -> Void
    func append(_: any Component, id: Entity.ID) -> Void
    func get(_: Entity.ID) -> any Component
    func `set`(_: Entity.ID, newValue: any Component) -> Void
    var entityToComponents: ContiguousArray<ContiguousArray.Index> { get }
    var componentsToEntites: ContiguousArray<SlotIndex> { get }

    @inlinable @inline(__always)
    func ensureEntity(_ entityID: Entity.ID)
}

@usableFromInline
final class ComponentArrayBox<C: Component>: AnyComponentArrayBox {
    @usableFromInline
    var base: ComponentArray<C>

    init(_ base: ComponentArray<C>) {
        self.base = base
    }

    @inlinable @inline(__always)
    func remove(id: Entity.ID) -> Void {
        base.remove(id)
    }

    @inlinable @inline(__always)
    func append(_ component: any Component, id: Entity.ID) -> Void {
        base.append(component as! C, to: id)
    }

    @inlinable @inline(__always)
    func get(_ id: Entity.ID) -> any Component {
        base[id]
    }

    @inlinable @inline(__always)
    func `set`(_ id: Entity.ID, newValue: any Component) -> Void {
        base[id] = newValue as! C
    }

    @inlinable @inline(__always)
    var entityToComponents: ContiguousArray<ContiguousArray.Index> {
        _read {
            yield base.slots
        }
    }

    @inlinable @inline(__always)
    var componentsToEntites: ContiguousArray<SlotIndex> {
        _read {
            yield base.entities
        }
    }

    @inlinable @inline(__always)
    func ensureEntity(_ entityID: Entity.ID) {
        base.ensureEntity(entityID)
    }
    
    @inlinable @inline(__always)
    subscript(entityID entityID: Entity.ID) -> C {
        _read { yield base[entityID] }
        _modify { yield &base[entityID] }
    }

    @inlinable @inline(__always)
    subscript(index index: Array.Index) -> C {
        _read { yield base[index] }
        _modify { yield &base[index] }
    }
}

public struct AnyComponentArray {
    @usableFromInline
    internal var base: any AnyComponentArrayBox

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

    @usableFromInline
    var entityToComponents: ContiguousArray<ContiguousArray.Index> {
        _read {
            yield base.entityToComponents
        }
    }

    @usableFromInline
    var componentsToEntites: ContiguousArray<SlotIndex> {
        _read {
            yield base.componentsToEntites
        }
    }

    @usableFromInline
    func typedBox<C: Component>(_ of: C.Type) -> ComponentArrayBox<C> {
        return base as! ComponentArrayBox<C>
    }

    public func withBuffer<C: Component, Result>(
        _ of: C.Type,
        _ body: (UnsafeMutableBufferPointer<C>, ContiguousArray<ContiguousArray.Index>) throws -> Result
    ) rethrows -> Result {
        let typed = base as! ComponentArrayBox<C>
        let indices = typed.entityToComponents
        return try typed.base.withUnsafeMutableBufferPointer { buffer in
             try body(buffer, indices)
        }
    }

    @inlinable @inline(__always)
    func ensureEntity(_ entityID: Entity.ID) {
        base.ensureEntity(entityID)
    }
}

extension ContiguousArray.Index {
    @usableFromInline
    static let notFound: ContiguousArray.Index = -1
}

public struct ComponentArray<Component: Components.Component>: Collection {
    @usableFromInline
    private(set) var components: ContiguousArray<Component> = []
    @usableFromInline
    private(set) var slots: ContiguousArray<ContiguousArray.Index> = [] // Indexed by SlotIndex.
    @usableFromInline
    private(set) var entities: ContiguousArray<SlotIndex> = [] // Indexed by component index.

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
        entityID.slot.rawValue < slots.count && slots[entityID.slot.rawValue] != .notFound
    }

    @inlinable @inline(__always)
    mutating public func ensureEntity(_ entityID: Entity.ID) {
        if !slots.indices.contains(entityID.slot.rawValue) {
            let missingCount = (entityID.slot.rawValue + 1) - slots.count
            slots.append(contentsOf: repeatElement(.notFound, count: missingCount))
        }
    }

    @inlinable @inline(__always)
    public mutating func append(_ component: Component, to entityID: Entity.ID) {
        components.append(component)
        entities.append(entityID.slot)
        if !slots.indices.contains(entityID.slot.rawValue) {
            let missingCount = (entityID.slot.rawValue + 1) - slots.count
            slots.append(contentsOf: repeatElement(.notFound, count: missingCount))
        }
        slots[entityID.slot.rawValue] = components.endIndex - 1
    }

    @inlinable @inline(__always)
    public mutating func remove(_ entityID: Entity.ID) {
        guard slots.indices.contains(entityID.slot.rawValue) else { return }
        let componentIndex = slots[entityID.slot.rawValue]
        guard componentIndex != components.endIndex - 1 else {
            entities.removeLast()
            slots[entityID.slot.rawValue] = .notFound
            components.removeLast()
            return
        }

        guard let lastComponentSlot = entities.popLast() else {
            fatalError("Missing entity for last component.")
        }
        components[componentIndex] = components.removeLast()
        entities[componentIndex] = lastComponentSlot
        slots[lastComponentSlot.rawValue] = componentIndex
        slots[entityID.slot.rawValue] = .notFound
    }

    @inlinable @inline(__always)
    public subscript(_ entityID: Entity.ID) -> Component {
        _read {
            yield components[slots[entityID.slot.rawValue]]
        }
        _modify {
            yield &components[slots[entityID.slot.rawValue]]
        }
    }

    public var startIndex: ContiguousArray.Index { components.startIndex }
    public var endIndex: ContiguousArray.Index { components.endIndex }

    public func index(after i: ContiguousArray.Index) -> ContiguousArray.Index {
        components.index(after: i)
    }

    @inlinable @inline(__always)
    public subscript(position: ContiguousArray.Index) -> Component {
        _read {
            yield components[position]
        }
        _modify {
            yield &components[position]
        }
    }
}

