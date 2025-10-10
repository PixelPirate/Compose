//
//  TypedAccess.swift
//  Components
//
//  Created by Patrick Horlebein (extern) on 10.10.25.
//

public struct TypedAccess<C: ComponentResolving>: @unchecked Sendable {
    @usableFromInline internal var buffer: UnsafeMutableBufferPointer<C.QueriedComponent>
    @usableFromInline internal var indices: ContiguousArray<ContiguousArray.Index?>

    @usableFromInline
    init(buffer: UnsafeMutableBufferPointer<C.QueriedComponent>, indices: ContiguousArray<ContiguousArray.Index?>) {
        self.buffer = buffer
        self.indices = indices
    }

    @inlinable @inline(__always)
    public subscript(_ id: Entity.ID) -> C.QueriedComponent {
        _read {
            yield buffer[indices[id.slot.rawValue].unsafelyUnwrapped]
        }
        nonmutating _modify {
            yield &buffer[indices[id.slot.rawValue].unsafelyUnwrapped]
        }
    }

    @inlinable @inline(__always)
    public subscript(optional id: Entity.ID) -> C.QueriedComponent? {
        _read {
            guard id.slot.rawValue < indices.count, let index = indices[id.slot.rawValue] else {
                yield nil
                return
            }
            yield buffer[index]
        }
        nonmutating _modify {
            var wrapped: Optional<C.QueriedComponent>
            if let index = indices[id.slot.rawValue] {
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
    public func access(_ id: Entity.ID) -> SingleTypedAccess<C.QueriedComponent> {
        SingleTypedAccess(buffer: buffer.baseAddress.unsafelyUnwrapped.advanced(by: indices[id.slot.rawValue].unsafelyUnwrapped))
    }

    @inlinable @inline(__always)
    public func optionalAccess(_ id: Entity.ID) -> SingleTypedAccess<C.QueriedComponent>? {
        guard id.slot.rawValue < indices.count, let index = indices[id.slot.rawValue] else {
            return nil
        }
        return SingleTypedAccess(buffer: buffer.baseAddress.unsafelyUnwrapped.advanced(by: indices[id.slot.rawValue].unsafelyUnwrapped))
    }
}

extension TypedAccess {
    @inlinable @inline(__always)
    static var empty: TypedAccess {
        // a harmless instance that never resolves anything
        TypedAccess(
            buffer: UnsafeMutableBufferPointer(start: nil, count: 0),
            indices: []
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
