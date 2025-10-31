public struct TypedAccess<C: ComponentResolving>: @unchecked Sendable {
    @usableFromInline internal var pointer: DenseSpan<C.QueriedComponent>
    @usableFromInline internal var indices: SlotsSpan<ContiguousArray.Index, SlotIndex>
    @usableFromInline internal var cursor: UnsafeMutablePointer<DenseSpanCursor<C.QueriedComponent>>?

    @usableFromInline
    init(
        pointer: DenseSpan<C.QueriedComponent>,
        indices: SlotsSpan<ContiguousArray.Index, SlotIndex>,
        cursor: UnsafeMutablePointer<DenseSpanCursor<C.QueriedComponent>>? = nil
    ) {
        self.pointer = pointer
        self.indices = indices
        self.cursor = cursor
    }

    @inlinable @inline(__always)
    public subscript(_ id: Entity.ID) -> C.QueriedComponent {
        _read {
            let denseIndex = indices[id.slot]
            yield pointerForDenseIndex(denseIndex).pointee
        }
        nonmutating _modify {
            let denseIndex = indices[id.slot]
            yield &pointerForDenseIndex(denseIndex).pointee
        }
    }

    @inlinable @inline(__always)
    public subscript(optional id: Entity.ID) -> C.QueriedComponent? {
        _read {
            let index = indices[checked: id.slot]
            guard index != .notFound else {
                yield nil
                return
            }
            yield pointerForDenseIndex(index).pointee
        }
        nonmutating _modify {
            var wrapped: Optional<C.QueriedComponent>
            let index = indices[id.slot]
            if index != .notFound {
                wrapped = Optional(pointerForDenseIndex(index).pointee)
                yield &wrapped
                guard let newValue = wrapped else {
                    fatalError("Removal of component through `Optional` not supported.")
                }
                pointerForDenseIndex(index).pointee = newValue
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
        _read { yield pointerForDenseIndex(denseIndex).pointee }
        nonmutating _modify { yield &pointerForDenseIndex(denseIndex).pointee }
    }

    @inlinable @inline(__always)
    public func accessDense(_ denseIndex: Int) -> SingleTypedAccess<C.QueriedComponent> {
        SingleTypedAccess(buffer: pointerForDenseIndex(denseIndex))
    }

    @inlinable @inline(__always)
    public func access(_ id: Entity.ID) -> SingleTypedAccess<C.QueriedComponent> {
        SingleTypedAccess(buffer: pointerForDenseIndex(indices[id.slot]))
    }

    @inlinable @inline(__always)
    public func optionalAccess(_ id: Entity.ID) -> SingleTypedAccess<C.QueriedComponent>? {
        let index = indices[checked: id.slot]
        guard index != .notFound else {
            return nil
        }
        return SingleTypedAccess(buffer: pointerForDenseIndex(indices[id.slot]))
    }
}

extension TypedAccess {
    @inlinable @inline(__always)
    static var empty: TypedAccess {
        TypedAccess(
            pointer: DenseSpan(
                view: UnsafeMutableBufferPointer<UnsafeMutablePointer<C.QueriedComponent>>(start: nil, count: 0)
            ),
            indices: SlotsSpan(
                view: UnsafeMutableBufferPointer<UnsafeMutablePointer<ContiguousArray<Void>.Index>>(start: nil, count: 0)
            ),
            cursor: nil
        )
    }
}

extension TypedAccess {
    @inlinable @inline(__always)
    func withCursor(
        _ cursor: UnsafeMutablePointer<DenseSpanCursor<C.QueriedComponent>>
    ) -> TypedAccess<C> {
        TypedAccess(pointer: pointer, indices: indices, cursor: cursor)
    }

    @inlinable @inline(__always)
    func pointerForDenseIndex(_ index: Int) -> UnsafeMutablePointer<C.QueriedComponent> {
        if let cursor {
            return cursor.pointee.pointer(for: index, pages: pointer.pages)
        }
        return pointer.mutablePointer(at: index)
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
