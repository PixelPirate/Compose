//
//  TypedAccess.swift
//  Components
//
//  Created by Patrick Horlebein (extern) on 10.10.25.
//

public struct TypedAccess<C: ComponentResolving>: @unchecked Sendable {
    @usableFromInline internal var buffer: UnsafeMutableBufferPointer<C.QueriedComponent>
    @usableFromInline internal var indices: SparseArray<ContiguousArray.Index, SlotIndex>.Values

    @usableFromInline
    init(buffer: UnsafeMutableBufferPointer<C.QueriedComponent>, indices: SparseArray<ContiguousArray.Index, SlotIndex>.Values) {
        self.buffer = buffer
        self.indices = indices
    }

    @inlinable @inline(__always)
    public subscript(_ id: Entity.ID) -> C.QueriedComponent {
        _read {
            yield buffer[indices[id.slot.rawValue]]
        }
        nonmutating _modify {
            yield &buffer[indices[id.slot.rawValue]]
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
            yield buffer[index]
        }
        nonmutating _modify {
            var wrapped: Optional<C.QueriedComponent>
            let index = indices[id.slot.rawValue]
            if index != .notFound {
                wrapped = Optional(buffer[index])
                yield &wrapped
                guard let newValue = wrapped else {
                    fatalError("Removal of component through `Optional` not supported.")
                }
                buffer[index] = newValue
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
        _read { yield buffer[denseIndex] }
        nonmutating _modify { yield &buffer[denseIndex] }
    }

    @inlinable @inline(__always)
    public func accessDense(_ denseIndex: Int) -> SingleTypedAccess<C.QueriedComponent> {
        SingleTypedAccess(buffer: buffer.baseAddress!.advanced(by: denseIndex))
    }

    @inlinable @inline(__always)
    public func access(_ id: Entity.ID) -> SingleTypedAccess<C.QueriedComponent> {
        SingleTypedAccess(buffer: buffer.baseAddress.unsafelyUnwrapped.advanced(by: indices[id.slot.rawValue]))
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
        return SingleTypedAccess(buffer: buffer.baseAddress.unsafelyUnwrapped.advanced(by: indices[id.slot.rawValue]))
    }
}

extension TypedAccess {
    @inlinable @inline(__always)
    static var empty: TypedAccess {
        // a harmless instance that never resolves anything
        TypedAccess(
            buffer: UnsafeMutableBufferPointer(start: nil, count: 0),
            indices: SparseArray<ContiguousArray.Index, SlotIndex>().values
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
