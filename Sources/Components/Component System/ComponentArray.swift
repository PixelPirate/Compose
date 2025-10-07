public typealias ComponentArray<C: Component> = SparseSet<C, SlotIndex>

extension SlotIndex: SparseSetIndex {
    @inlinable @inline(__always)
    public var index: Int {
        _read {
            yield self.rawValue
        }
    }

    @inlinable @inline(__always)
    public init(index: Int) {
        self = SlotIndex(rawValue: index)
    }
}

public protocol AnyComponentArrayBox: AnyObject {
    @inlinable @inline(__always)
    func remove(id: Entity.ID) -> Void

    @inlinable @inline(__always)
    func append<C: Component>(_: C, id: Entity.ID) -> Void

    @inlinable @inline(__always)
    func get(_: Entity.ID) -> any Component

    @inlinable @inline(__always)
    func `set`(_: Entity.ID, newValue: any Component) -> Void

    @inlinable @inline(__always)
    var entityToComponents: ContiguousArray<ContiguousArray.Index?> { get }

    @inlinable @inline(__always)
    var componentsToEntites: ContiguousArray<SlotIndex> { get }

    @inlinable @inline(__always)
    func ensureEntity(_ entityID: Entity.ID)

    @inlinable @inline(__always)
    func reserveCapacity(minimumComponentCapacity: Int, minimumSlotCapacity: Int)
}

@usableFromInline
final class ComponentArrayBox<C: Component>: AnyComponentArrayBox {
    @usableFromInline
    var base: SparseSet<C, SlotIndex>

    @usableFromInline
    init(_ base: SparseSet<C, SlotIndex>) {
        self.base = base
    }

    @inlinable @inline(__always)
    func remove(id: Entity.ID) -> Void {
        base.remove(id.slot)
    }

    @inlinable @inline(__always)
    func append<C1: Component>(_ component: C1, id: Entity.ID) {
        base.append(unsafeBitCast(component, to: C.self), to: id.slot)
    }

    @inlinable @inline(__always)
    func get(_ id: Entity.ID) -> any Component {
        base[slot: id.slot]
    }

    @inlinable @inline(__always)
    func `set`(_ id: Entity.ID, newValue: any Component) -> Void {
        base[slot: id.slot] = newValue as! C
    }

    @inlinable @inline(__always)
    var entityToComponents: ContiguousArray<ContiguousArray.Index?> {
        _read {
            yield base.slots.values
        }
    }

    @inlinable @inline(__always)
    var componentsToEntites: ContiguousArray<SlotIndex> {
        _read {
            yield base.keys
        }
    }

    @inlinable @inline(__always)
    func ensureEntity(_ entityID: Entity.ID) {
        base.ensureEntity(entityID.slot)
    }

    @inlinable @inline(__always)
    subscript(entityID entityID: Entity.ID) -> C {
        _read { yield base[slot: entityID.slot] }
        _modify { yield &base[slot: entityID.slot] }
    }

    @inlinable @inline(__always)
    subscript(index index: Array.Index) -> C {
        _read { yield base[index] }
        _modify { yield &base[index] }
    }

    @inlinable @inline(__always)
    func reserveCapacity(minimumComponentCapacity: Int, minimumSlotCapacity: Int) {
        base.reserveCapacity(minimumComponentCapacity: minimumComponentCapacity, minimumSlotCapacity: minimumSlotCapacity)
    }
}

public struct AnyComponentArray {
    @usableFromInline
    internal let base: any AnyComponentArrayBox

    @inlinable @inline(__always)
    public init<C: Component>(_ base: SparseSet<C, SlotIndex>) {
        self.base = ComponentArrayBox(base)
    }

    @inlinable @inline(__always)
    public func remove(_ entityID: Entity.ID) {
        base.remove(id: entityID)
    }

    @inlinable @inline(__always)
    public func append<C: Component>(_ component: C, id: Entity.ID) {
        base.append(component, id: id)
    }

    @inlinable @inline(__always)
    public subscript(entityID entityID: Entity.ID) -> any Component {
        _read {
            yield base.get(entityID)
        }
        set {
            base.set(entityID, newValue: newValue)
        }
    }

    @usableFromInline
    var entityToComponents: ContiguousArray<ContiguousArray.Index?> {
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
        base as! ComponentArrayBox<C>
    }

    public func withBuffer<C: Component, Result>(
        _ of: C.Type,
        _ body: (UnsafeMutableBufferPointer<C>, ContiguousArray<ContiguousArray.Index?>) throws -> Result
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

    @inlinable @inline(__always)
    public mutating func reserveCapacity(minimumComponentCapacity: Int, minimumSlotCapacity: Int) {
        base.reserveCapacity(minimumComponentCapacity: minimumComponentCapacity, minimumSlotCapacity: minimumSlotCapacity)
    }
}
