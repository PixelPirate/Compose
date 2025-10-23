//
//  TypedAccess.swift
//  Components
//
//  Created by Patrick Horlebein (extern) on 10.10.25.
//

public struct TypedAccess<C: ComponentResolving>: @unchecked Sendable {
    @usableFromInline internal var storage: UnsafeMutablePointer<PagedArray<C.QueriedComponent>>
    @usableFromInline internal var indices: PagedArray<ContiguousArray.Index>

    @usableFromInline
    init(storage: UnsafeMutablePointer<PagedArray<C.QueriedComponent>>, indices: PagedArray<ContiguousArray.Index>) {
        self.storage = storage
        self.indices = indices
    }

    @inlinable @inline(__always)
    public subscript(_ id: Entity.ID) -> C.QueriedComponent {
        _read {
            let denseIndex = indices[id.slot.rawValue]
            let pointer = storage.pointee.pointer(at: denseIndex)
            yield pointer.pointee
        }
        nonmutating _modify {
            let denseIndex = indices[id.slot.rawValue]
            let pointer = storage.pointee.mutablePointer(at: denseIndex)
            yield &pointer.pointee
        }
    }

    @inlinable @inline(__always)
    public subscript(optional id: Entity.ID) -> C.QueriedComponent? {
        _read {
            guard id.slot.rawValue < indices.count else {
                yield nil
                return
            }
            let index = indices[id.slot.rawValue]
            guard index != .notFound else {
                yield nil
                return
            }
            let pointer = storage.pointee.pointer(at: index)
            yield pointer.pointee
        }
        nonmutating _modify {
            var wrapped: Optional<C.QueriedComponent>
            let index = indices[id.slot.rawValue]
            if index != .notFound {
                let pointer = storage.pointee.mutablePointer(at: index)
                wrapped = Optional(pointer.pointee)
                yield &wrapped
                guard let newValue = wrapped else {
                    fatalError("Removal of component through `Optional` not supported.")
                }
                pointer.pointee = newValue
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
            let pointer = storage.pointee.pointer(at: denseIndex)
            yield pointer.pointee
        }
        nonmutating _modify {
            let pointer = storage.pointee.mutablePointer(at: denseIndex)
            yield &pointer.pointee
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
        let index = indices[id.slot.rawValue]
        guard index != .notFound else {
            return nil
        }
        return SingleTypedAccess(storage: storage, denseIndex: indices[id.slot.rawValue])
    }
}

extension TypedAccess {
    @inlinable @inline(__always)
    static var empty: TypedAccess {
        // a harmless instance that never resolves anything
        TypedAccess(
            storage: UnsafeMutablePointer<PagedArray<C.QueriedComponent>>.allocate(capacity: 0),
            indices: []
        )
    }
}

public struct SingleTypedAccess<C: Component> {
    @usableFromInline internal var pointer: UnsafeMutablePointer<C>

    @inlinable @inline(__always)
    init(storage: UnsafeMutablePointer<PagedArray<C>>, denseIndex: Int) {
        self.pointer = storage.pointee.mutablePointer(at: denseIndex)
    }

    @inlinable @inline(__always)
    public var value: C {
        _read { yield pointer.pointee }
        nonmutating _modify { yield &pointer.pointee }
    }
}
