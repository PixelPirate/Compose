//
//  TypedAccess.swift
//  Components
//
//  Created by Patrick Horlebein (extern) on 10.10.25.
//

public struct TypedAccess<C: ComponentResolving>: @unchecked Sendable {
    @usableFromInline internal unowned(safe) var box: ComponentArrayBox<C.QueriedComponent>

    @usableFromInline
    init(box: ComponentArrayBox<C.QueriedComponent>) {
        self.box = box
    }

    @inlinable @inline(__always)
    public subscript(_ id: Entity.ID) -> C.QueriedComponent {
        _read {
            yield box.base[slot: id.slot]
        }
        nonmutating _modify {
            yield &box.base[slot: id.slot]
        }
    }

    @inlinable @inline(__always)
    public subscript(optional id: Entity.ID) -> C.QueriedComponent? {
        _read {
            let slots = box.base.slots
            guard id.slot.rawValue < slots.count else {
                yield nil
                return
            }
            let index = slots[id.slot]
            guard index != .notFound else {
                yield nil
                return
            }
            yield box.base[index]
        }
        nonmutating _modify {
            var wrapped: Optional<C.QueriedComponent>
            let slots = box.base.slots
            let index = slots[id.slot]
            if index != .notFound {
                wrapped = Optional(box.base[index])
                yield &wrapped
                guard let newValue = wrapped else {
                    fatalError("Removal of component through `Optional` not supported.")
                }
                box.base[index] = newValue
            } else {
                wrapped = nil
                yield &wrapped
                guard wrapped == nil else {
                    fatalError("Insertion of component through `Optional` not supported.")
                }
            }
        }
    }

    @inlinable @inline(__always)
    public subscript(dense denseIndex: Int) -> C.QueriedComponent {
        _read { yield box.base[denseIndex] }
        nonmutating _modify { yield &box.base[denseIndex] }
    }

    @inlinable @inline(__always)
    public func accessDense(_ denseIndex: Int) -> SingleTypedAccess<C.QueriedComponent> {
        SingleTypedAccess(box: box, denseIndex: denseIndex)
    }

    @inlinable @inline(__always)
    public func access(_ id: Entity.ID) -> SingleTypedAccess<C.QueriedComponent> {
        SingleTypedAccess(box: box, denseIndex: box.base.componentIndex(id.slot))
    }

    @inlinable @inline(__always)
    public func optionalAccess(_ id: Entity.ID) -> SingleTypedAccess<C.QueriedComponent>? {
        // TODO: Fix warning.
        let slots = box.base.slots
        guard id.slot.rawValue < slots.count else {
            return nil
        }
        let index = slots[id.slot]
        guard index != .notFound else {
            return nil
        }
        return SingleTypedAccess(box: box, denseIndex: index)
    }
}

public struct SingleTypedAccess<C: Component> {
    @usableFromInline internal unowned(unsafe) var box: ComponentArrayBox<C>
    @usableFromInline internal var denseIndex: Int

    @inlinable @inline(__always)
    init(box: ComponentArrayBox<C>, denseIndex: Int) {
        self.box = box
        self.denseIndex = denseIndex
    }

    @inlinable @inline(__always)
    public var value: C {
        _read {
            yield box.base[denseIndex]
        }
        nonmutating _modify {
            yield &box.base[denseIndex]
        }
    }
}
