//
//  TypedAccess.swift
//  Components
//
//  Created by Patrick Horlebein (extern) on 10.10.25.
//

public struct TypedAccess<C: ComponentResolving>: @unchecked Sendable {
    @usableFromInline internal var storage: UnsafeMutablePointer<PagedArray<C.QueriedComponent>>
    @usableFromInline internal var indices: UnsafeMutablePointer<PagedArray<ContiguousArray.Index>>

    @usableFromInline
    init(
        storage: UnsafeMutablePointer<PagedArray<C.QueriedComponent>>,
        indices: UnsafeMutablePointer<PagedArray<ContiguousArray.Index>>
    ) {
        self.storage = storage
        self.indices = indices
    }

    @inlinable @inline(__always)
    public subscript(_ id: Entity.ID) -> C.QueriedComponent {
        _read {
            yield storage.pointee[indices.pointee[id.slot.rawValue]]
        }
        nonmutating _modify {
            yield &storage.pointee[indices.pointee[id.slot.rawValue]]
        }
    }

    @inlinable @inline(__always)
    public subscript(optional id: Entity.ID) -> C.QueriedComponent? {
        _read {
            guard id.slot.rawValue < indices.pointee.count else {
                yield nil
                return
            }
            let index = indices.pointee[id.slot.rawValue]
            guard index != .notFound else {
                yield nil
                return
            }
            yield storage.pointee[index]
        }
        nonmutating _modify {
            var wrapped: Optional<C.QueriedComponent>
            let index = indices.pointee[id.slot.rawValue]
            if index != .notFound {
                wrapped = Optional(storage.pointee[index])
                yield &wrapped
                guard let newValue = wrapped else {
                    fatalError("Removal of component through `Optional` not supported.")
                }
                storage.pointee[index] = newValue
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
        _read { yield storage.pointee[denseIndex] }
        nonmutating _modify { yield &storage.pointee[denseIndex] }
    }

    @inlinable @inline(__always)
    public func accessDense(_ denseIndex: Int) -> SingleTypedAccess<C.QueriedComponent> {
        SingleTypedAccess(storage: storage, denseIndex: denseIndex)
    }

    @inlinable @inline(__always)
    public func access(_ id: Entity.ID) -> SingleTypedAccess<C.QueriedComponent> {
        SingleTypedAccess(storage: storage, denseIndex: indices.pointee[id.slot.rawValue])
    }

    @inlinable @inline(__always)
    public func optionalAccess(_ id: Entity.ID) -> SingleTypedAccess<C.QueriedComponent>? {
        // TODO: Fix warning.
        guard id.slot.rawValue < indices.pointee.count else {
            return nil
        }
        let index = indices.pointee[id.slot.rawValue]
        guard index != .notFound else {
            return nil
        }
        return SingleTypedAccess(storage: storage, denseIndex: indices.pointee[id.slot.rawValue])
    }
}

extension TypedAccess {
    @inlinable @inline(__always)
    static var empty: TypedAccess {
        // a harmless instance that never resolves anything
        let storage = UnsafeMutablePointer<PagedArray<C.QueriedComponent>>.allocate(capacity: 1)
        storage.initialize(to: PagedArray())
        let indices = UnsafeMutablePointer<PagedArray<ContiguousArray.Index>>.allocate(capacity: 1)
        indices.initialize(to: PagedArray())
        return TypedAccess(storage: storage, indices: indices)
    }
}

public struct SingleTypedAccess<C: Component> {
    @usableFromInline internal var storage: UnsafeMutablePointer<PagedArray<C>>
    @usableFromInline internal var denseIndex: Int

    @inlinable @inline(__always)
    init(storage: UnsafeMutablePointer<PagedArray<C>>, denseIndex: Int) {
        self.storage = storage
        self.denseIndex = denseIndex
    }

    @inlinable @inline(__always)
    public var value: C {
        _read {
            yield storage.pointee[denseIndex]
        }
        nonmutating _modify {
            yield &storage.pointee[denseIndex]
        }
    }
}
