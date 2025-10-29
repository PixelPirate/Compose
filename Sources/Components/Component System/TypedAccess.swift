//
//  TypedAccess.swift
//  Components
//
//  Created by Patrick Horlebein (extern) on 10.10.25.
//

public struct TypedAccess<C: ComponentResolving>: @unchecked Sendable {
    @usableFromInline internal var pointer: UnsafeMutablePointer<C.QueriedComponent>
    @usableFromInline internal var indices: UnsafePagedStorage<ContiguousArray.Index>

    @usableFromInline
    init(pointer: UnsafeMutablePointer<C.QueriedComponent>, indices: UnsafePagedStorage<ContiguousArray.Index>) {
        self.pointer = pointer
        self.indices = indices
    }

    @inlinable @inline(__always)
    public subscript(_ id: Entity.ID) -> C.QueriedComponent {
        _read {
            yield pointer[indices[id.slot.rawValue]]
        }
        nonmutating _modify {
            yield &pointer[indices[id.slot.rawValue]]
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
            yield pointer[index]
        }
        nonmutating _modify {
            var wrapped: Optional<C.QueriedComponent>
            let index = indices[id.slot.rawValue]
            if index != .notFound {
                wrapped = Optional(pointer[index])
                yield &wrapped
                guard let newValue = wrapped else {
                    fatalError("Removal of component through `Optional` not supported.")
                }
                pointer[index] = newValue
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
        _read { yield pointer[denseIndex] }
        nonmutating _modify { yield &pointer[denseIndex] }
    }

    @inlinable @inline(__always)
    public func accessDense(_ denseIndex: Int) -> SingleTypedAccess<C.QueriedComponent> {
        SingleTypedAccess(buffer: pointer.advanced(by: denseIndex))
    }

    @inlinable @inline(__always)
    public func access(_ id: Entity.ID) -> SingleTypedAccess<C.QueriedComponent> {
        SingleTypedAccess(buffer: pointer.advanced(by: indices[id.slot.rawValue]))
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
        return SingleTypedAccess(buffer: pointer.advanced(by: indices[id.slot.rawValue]))
    }
}

extension TypedAccess {
    @inlinable @inline(__always)
    static var empty: TypedAccess {
        // a harmless instance that never resolves anything
        TypedAccess(
            pointer: .allocate(capacity: 0),
            indices: UnsafePagedStorage(PagedStorage(initialPageCapacity: 1))
        )
    }
}

public struct SingleTypedAccess<C: Component> {
    @usableFromInline internal var buffer: UnsafeMutablePointer<C>

    @inlinable @inline(__always)
    init(buffer: UnsafeMutablePointer<C>) {
        self.buffer = buffer
    }

    @inlinable @inline(__always)
    public var value: C {
        _read {
            yield buffer.pointee
        }
        nonmutating _modify {
            yield &buffer.pointee
        }
    }
}
