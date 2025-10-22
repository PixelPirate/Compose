//
//  TypedAccess.swift
//  Components
//
//  Created by Patrick Horlebein (extern) on 10.10.25.
//

@usableFromInline
enum EmptyComponentArrayStorage<C: Component> {
    @usableFromInline
    static let box = ComponentArrayBox<C>(SparseSet<C, SlotIndex>())
}

public struct TypedAccess<C: ComponentResolving>: @unchecked Sendable {
    @usableFromInline internal var storage: Unmanaged<ComponentArrayBox<C.QueriedComponent>>
    @usableFromInline internal var indices: PagedArray<ContiguousArray.Index>

    @usableFromInline
    init(storage: Unmanaged<ComponentArrayBox<C.QueriedComponent>>, indices: PagedArray<ContiguousArray.Index>) {
        self.storage = storage
        self.indices = indices
    }

    @inlinable @inline(__always)
    public subscript(_ id: Entity.ID) -> C.QueriedComponent {
        _read {
            let box = storage.takeUnretainedValue()
            yield box[entityID: id]
        }
        nonmutating _modify {
            let box = storage.takeUnretainedValue()
            yield &box[entityID: id]
        }
    }

    @inlinable @inline(__always)
    public subscript(optional id: Entity.ID) -> C.QueriedComponent? {
        _read {
            guard id.slot.rawValue < indices.count else {
                yield nil
                return
            }
            let denseIndex = indices[id.slot.rawValue]
            guard denseIndex != .notFound else {
                yield nil
                return
            }
            let box = storage.takeUnretainedValue()
            yield box[index: denseIndex]
        }
        nonmutating _modify {
            var wrapped: Optional<C.QueriedComponent>
            let denseIndex = indices[id.slot.rawValue]
            if denseIndex != .notFound {
                let box = storage.takeUnretainedValue()
                wrapped = Optional(box[index: denseIndex])
                yield &wrapped
                guard let newValue = wrapped else {
                    fatalError("Removal of component through `Optional` not supported.")
                }
                box[index: denseIndex] = newValue
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
        _read {
            let box = storage.takeUnretainedValue()
            yield box[index: denseIndex]
        }
        nonmutating _modify {
            let box = storage.takeUnretainedValue()
            yield &box[index: denseIndex]
        }
    }

    @inlinable @inline(__always)
    public func accessDense(_ denseIndex: Int) -> SingleTypedAccess<C.QueriedComponent> {
        SingleTypedAccess(storage: storage, denseIndex: denseIndex)
    }

    @inlinable @inline(__always)
    public func access(_ id: Entity.ID) -> SingleTypedAccess<C.QueriedComponent> {
        SingleTypedAccess(storage: storage, denseIndex: indices[id.slot.rawValue])
    }

    @inlinable @inline(__always)
    public func optionalAccess(_ id: Entity.ID) -> SingleTypedAccess<C.QueriedComponent>? {
        // TODO: Fix warning.
        guard id.slot.rawValue < indices.count else {
            return nil
        }
        let denseIndex = indices[id.slot.rawValue]
        guard denseIndex != .notFound else {
            return nil
        }
        return SingleTypedAccess(storage: storage, denseIndex: denseIndex)
    }
}

extension TypedAccess {
    @inlinable @inline(__always)
    static var empty: TypedAccess {
        // a harmless instance that never resolves anything
        TypedAccess(
            storage: Unmanaged.passUnretained(EmptyComponentArrayStorage<C.QueriedComponent>.box),
            indices: []
        )
    }
}

public struct SingleTypedAccess<C: Component> {
    @usableFromInline internal var storage: Unmanaged<ComponentArrayBox<C>>
    @usableFromInline internal var denseIndex: Int

    @inlinable @inline(__always)
    init(storage: Unmanaged<ComponentArrayBox<C>>, denseIndex: Int) {
        self.storage = storage
        self.denseIndex = denseIndex
    }

    @inlinable @inline(__always)
    public var value: C {
        _read {
            let box = storage.takeUnretainedValue()
            yield box[index: denseIndex]
        }
        nonmutating _modify {
            let box = storage.takeUnretainedValue()
            yield &box[index: denseIndex]
        }
    }
}
