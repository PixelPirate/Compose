public struct ComponentArray<C: Component> {
    @usableFromInline
    internal var storage: SparseSet<C, SlotIndex>
    @usableFromInline
    internal var ticks: PagedDense2<ComponentTicks>

    @inlinable @inline(__always)
    public init() {
        self.storage = SparseSet<C, SlotIndex>()
        self.ticks = PagedDense2<ComponentTicks>()
    }

    @inlinable @inline(__always)
    mutating func reserveCapacity(minimumComponentCapacity: Int, minimumSlotCapacity: Int) {
        storage.reserveCapacity(minimumComponentCapacity: minimumComponentCapacity, minimumSlotCapacity: minimumSlotCapacity)
        ticks.ensureCapacity(minimumComponentCapacity)
    }

    @inlinable @inline(__always)
    mutating func ensureEntity(_ entityID: Entity.ID) {
        storage.ensureEntity(entityID.slot)
    }

    @inlinable @inline(__always)
    mutating func append(_ component: C, to entityID: Entity.ID, changeTick: UInt64) {
        let slot = entityID.slot
        let denseIndex = storage.componentIndex(slot)
        if denseIndex != .notFound {
            storage[slot: slot] = component
            ticks[denseIndex].markChanged(at: changeTick)
            return
        }

        storage.append(component, to: slot)
        ticks.append(ComponentTicks(tick: changeTick))
    }

    @inlinable @inline(__always)
    mutating func set(_ component: C, for entityID: Entity.ID, changeTick: UInt64) {
        let slot = entityID.slot
        let denseIndex = storage.componentIndex(slot)
        precondition(denseIndex != .notFound, "Attempted to set a component that does not exist.")
        storage[slot: slot] = component
        ticks[denseIndex].markChanged(at: changeTick)
    }

    @inlinable @inline(__always)
    mutating func remove(_ entityID: Entity.ID) {
        remove(slot: entityID.slot)
    }

    @inlinable @inline(__always)
    mutating func remove(slot: SlotIndex) {
        let denseIndex = storage.componentIndex(slot)
        guard denseIndex != .notFound else { return }
        let lastIndex = storage.endIndex - 1
        if denseIndex != lastIndex {
            let movedTicks = ticks[lastIndex]
            _ = storage.remove(slot)
            ticks[denseIndex] = movedTicks
            _ = ticks.removeLast()
        } else {
            _ = storage.remove(slot)
            _ = ticks.removeLast()
        }
    }

    @inlinable @inline(__always)
    mutating func swapDenseAt(_ i: Int, _ j: Int) {
        guard i != j else { return }
        storage.swapDenseAt(i, j)
        ticks.swapAt(i, j)
    }

    @inlinable @inline(__always)
    mutating func partition(by belongsInSecondPartition: (SlotIndex) -> Bool) -> Int {
        let total = storage.count
        var write = 0
        var read = 0
        while read < total {
            let slot = storage.keys[read]
            if !belongsInSecondPartition(slot) {
                if read != write {
                    swapDenseAt(read, write)
                }
                write &+= 1
            }
            read &+= 1
        }
        return write
    }

    @inlinable @inline(__always)
    func ticks(for entityID: Entity.ID) -> ComponentTicks? {
        let denseIndex = storage.componentIndex(entityID.slot)
        guard denseIndex != .notFound else { return nil }
        return ticks[denseIndex]
    }

    @inlinable @inline(__always)
    func denseTicks(at index: Int) -> UnsafeMutablePointer<ComponentTicks> {
        ticks.mutablePointer(for: index)
    }

    @inlinable @inline(__always)
    var entityToComponents: SlotsSpan<ContiguousArray.Index, SlotIndex> {
        storage.slots.view
    }

    @inlinable @inline(__always)
    var componentsToEntites: ContiguousArray<SlotIndex> {
        storage.keys
    }

    @inlinable @inline(__always)
    var view: DenseSpan2<C> {
        storage.view
    }

    @inlinable @inline(__always)
    var tickView: DenseSpan2<ComponentTicks> {
        ticks.view
    }
}
public protocol AnyComponentArrayBox: AnyObject {
    @inlinable @inline(__always)
    func remove(id: Entity.ID)

    @inlinable @inline(__always)
    func append<C: Component>(_ component: C, id: Entity.ID, changeTick: UInt64)

    @inlinable @inline(__always)
    func get(_ id: Entity.ID) -> any Component

    @inlinable @inline(__always)
    func set(_ id: Entity.ID, newValue: any Component, changeTick: UInt64)

    @inlinable @inline(__always)
    var entityToComponents: SlotsSpan<ContiguousArray.Index, SlotIndex> { get }

    @inlinable @inline(__always)
    var componentsToEntites: ContiguousArray<SlotIndex> { get }

    @inlinable @inline(__always)
    func ensureEntity(_ entityID: Entity.ID)

    @inlinable @inline(__always)
    func reserveCapacity(minimumComponentCapacity: Int, minimumSlotCapacity: Int)

    @inlinable @inline(__always)
    func ticks(for entityID: Entity.ID) -> ComponentTicks?

    @inlinable @inline(__always)
    func withBuffer<C: Component, Result>(
        _ of: C.Type,
        _ body: (DenseSpan2<C>, SlotsSpan<ContiguousArray.Index, SlotIndex>, DenseSpan2<ComponentTicks>) throws -> Result
    ) rethrows -> Result

    @inlinable @inline(__always)
    func partition<C: Component>(
        _ type: C.Type,
        by belongsInSecondPartition: (SlotIndex) -> Bool
    ) -> Int

    @inlinable @inline(__always)
    func withMutableSparseSet<C: Component, R>(
        _ type: C.Type,
        _ body: (inout ComponentArray<C>) throws -> R
    ) rethrows -> R
}

@usableFromInline
final class ComponentArrayBox<C: Component>: AnyComponentArrayBox {
    @usableFromInline
    var base: ComponentArray<C>

    @usableFromInline
    init(_ base: ComponentArray<C> = ComponentArray<C>()) {
        self.base = base
    }

    @inlinable @inline(__always)
    func remove(id: Entity.ID) {
        base.remove(id)
    }

    @inlinable @inline(__always)
    func append<C1: Component>(_ component: C1, id: Entity.ID, changeTick: UInt64) {
        base.append(unsafeBitCast(component, to: C.self), to: id, changeTick: changeTick)
    }

    @inlinable @inline(__always)
    func get(_ id: Entity.ID) -> any Component {
        base.storage[slot: id.slot]
    }

    @inlinable @inline(__always)
    func set(_ id: Entity.ID, newValue: any Component, changeTick: UInt64) {
        base.set(newValue as! C, for: id, changeTick: changeTick)
    }

    @inlinable @inline(__always)
    var entityToComponents: SlotsSpan<ContiguousArray.Index, SlotIndex> {
        base.entityToComponents
    }

    @inlinable @inline(__always)
    var componentsToEntites: ContiguousArray<SlotIndex> {
        base.componentsToEntites
    }

    @inlinable @inline(__always)
    func ensureEntity(_ entityID: Entity.ID) {
        base.ensureEntity(entityID)
    }

    @inlinable @inline(__always)
    func reserveCapacity(minimumComponentCapacity: Int, minimumSlotCapacity: Int) {
        base.reserveCapacity(minimumComponentCapacity: minimumComponentCapacity, minimumSlotCapacity: minimumSlotCapacity)
    }

    @inlinable @inline(__always)
    func ticks(for entityID: Entity.ID) -> ComponentTicks? {
        base.ticks(for: entityID)
    }

    @inlinable @inline(__always)
    func withBuffer<C1: Component, Result>(
        _ of: C1.Type,
        _ body: (DenseSpan2<C1>, SlotsSpan<ContiguousArray.Index, SlotIndex>, DenseSpan2<ComponentTicks>) throws -> Result
    ) rethrows -> Result {
        precondition(C1.self == C.self, "Mismatched component type access.")
        let typed = unsafeBitCast(self, to: ComponentArrayBox<C1>.self)
        let indices = typed.entityToComponents
        return try body(typed.base.view, indices, typed.base.tickView)
    }

    @inlinable @inline(__always)
    func partition<C1: Component>(
        _ type: C1.Type,
        by belongsInSecondPartition: (SlotIndex) -> Bool
    ) -> Int {
        precondition(C1.self == C.self, "Mismatched component type access.")
        let typed = unsafeBitCast(self, to: ComponentArrayBox<C1>.self)
        return typed.base.partition(by: belongsInSecondPartition)
    }

    @inlinable @inline(__always)
    func withMutableSparseSet<C1: Component, R>(
        _ type: C1.Type,
        _ body: (inout ComponentArray<C1>) throws -> R
    ) rethrows -> R {
        precondition(C1.self == C.self, "Mismatched component type access.")
        let typed = unsafeBitCast(self, to: ComponentArrayBox<C1>.self)
        return try body(&typed.base)
    }
}

public struct AnyComponentArray {
    @usableFromInline
    internal let base: any AnyComponentArrayBox

    @inlinable @inline(__always)
    public init<C: Component>(_ base: ComponentArray<C>) {
        self.base = ComponentArrayBox(base)
    }

    @inlinable @inline(__always)
    public func remove(_ entityID: Entity.ID) {
        base.remove(id: entityID)
    }

    @inlinable @inline(__always)
    public func append<C: Component>(_ component: C, id: Entity.ID, changeTick: UInt64) {
        base.append(component, id: id, changeTick: changeTick)
    }

    @inlinable @inline(__always)
    public func set(_ entityID: Entity.ID, to newValue: any Component, changeTick: UInt64) {
        base.set(entityID, newValue: newValue, changeTick: changeTick)
    }

    @inlinable @inline(__always)
    public subscript(entityID entityID: Entity.ID) -> any Component {
        _read {
            yield base.get(entityID)
        }
    }

    @usableFromInline @inline(__always)
    var entityToComponents: SlotsSpan<ContiguousArray.Index, SlotIndex> {
        base.entityToComponents
    }

    @usableFromInline @inline(__always)
    var componentsToEntites: ContiguousArray<SlotIndex> {
        base.componentsToEntites
    }

    @usableFromInline @inline(__always)
    func typedBox<C: Component>(_ of: C.Type) -> ComponentArrayBox<C> {
        base as! ComponentArrayBox<C>
    }

    @inlinable @inline(__always)
    public func withBuffer<C: Component, Result>(
        _ of: C.Type,
        _ body: (DenseSpan2<C>, SlotsSpan<ContiguousArray.Index, SlotIndex>, DenseSpan2<ComponentTicks>) throws -> Result
    ) rethrows -> Result {
        try base.withBuffer(of, body)
    }

    @usableFromInline @inline(__always)
    func ensureEntity(_ entityID: Entity.ID) {
        base.ensureEntity(entityID)
    }

    @inlinable @inline(__always)
    public mutating func reserveCapacity(minimumComponentCapacity: Int, minimumSlotCapacity: Int) {
        base.reserveCapacity(minimumComponentCapacity: minimumComponentCapacity, minimumSlotCapacity: minimumSlotCapacity)
    }

    @inlinable @inline(__always)
    func ticks(for entityID: Entity.ID) -> ComponentTicks? {
        base.ticks(for: entityID)
    }

    @inlinable @inline(__always)
    mutating func partition<C: Component>(
        _ type: C.Type,
        by belongsInSecondPartition: (SlotIndex) -> Bool
    ) -> Int {
        base.partition(type, by: belongsInSecondPartition)
    }

    @inlinable @inline(__always)
    mutating func withMutableSparseSet<C: Component, R>(
        _ type: C.Type,
        _ body: (inout ComponentArray<C>) throws -> R
    ) rethrows -> R {
        try base.withMutableSparseSet(type, body)
    }
}
@discardableResult
@usableFromInline @inline(__always)
func withTypedBuffers<each C: ComponentResolving, R>(
    _ pool: inout ComponentPool,
    changeTick: UInt64,
    _ body: (repeat TypedAccess<each C>) throws -> R
) rethrows -> R {
    @inline(__always)
    func buildTuple() -> (repeat TypedAccess<each C>) {
        return (repeat tryMakeAccess((each C).self))
    }

    @inline(__always)
    func tryMakeAccess<D: ComponentResolving>(_ type: D.Type) -> TypedAccess<D> {
        guard D.QueriedComponent.self != Never.self else {
            return TypedAccess<D>.empty(changeTick: changeTick)
        }
        guard let anyArray = pool.components[D.QueriedComponent.componentTag] else {
            guard D.self is any OptionalQueriedComponent.Type else {
                fatalError("Unknown component.")
            }
            return TypedAccess<D>.empty(changeTick: changeTick)
        }
        var result: TypedAccess<D>? = nil
        anyArray.withBuffer(D.QueriedComponent.self) { pointer, entitiesToIndices, ticks in
            result = TypedAccess(pointer: pointer, indices: entitiesToIndices, ticks: ticks, changeTick: changeTick)
        }
        return result.unsafelyUnwrapped
    }

    return try body(repeat each buildTuple())
}
