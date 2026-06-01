public struct TypedAccess<C: ComponentResolving>: @unchecked Sendable {
    @usableFromInline internal var pointer: SparseSet<C.QueriedComponent, SlotIndex>.DenseSpan
    @usableFromInline internal var indices: SlotsSpan<ContiguousArray.Index, SlotIndex>
    @usableFromInline internal var ticks: MutableContiguousSpan<ComponentTicks>
    @usableFromInline internal let changeTick: UInt64
    @usableFromInline internal let tag: ComponentTag

    @usableFromInline
    init(
        pointer: SparseSet<C.QueriedComponent, SlotIndex>.DenseSpan,
        indices: SlotsSpan<ContiguousArray.Index, SlotIndex>,
        ticks: MutableContiguousSpan<ComponentTicks>,
        changeTick: UInt64
    ) {
        self.pointer = pointer
        self.indices = indices
        self.ticks = ticks
        self.changeTick = changeTick
        self.tag = C.QueriedComponent.componentTag
    }

    @inlinable @inline(__always)
    public subscript(_ id: Entity.ID) -> C.QueriedComponent {
        unsafeAddress {
            UnsafePointer(pointer.mutablePointer(at: indices[id.slot]))
        }
        nonmutating unsafeMutableAddress {
            let dense = indices[id.slot]
            markChanged(at: dense)
            return pointer.mutablePointer(at: dense)
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
            yield pointer[index]
        }
        nonmutating _modify {
            var wrapped: Optional<C.QueriedComponent>
            let index = indices[id.slot]
            if index != .notFound {
                wrapped = Optional(pointer[index])
                yield &wrapped
                guard let newValue = wrapped else {
                    fatalError("Removal of component through `Optional` not supported.")
                }
                pointer[index] = newValue
                markChanged(at: index)
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
        unsafeAddress {
            UnsafePointer(pointer.mutablePointer(at: denseIndex))
        }
        nonmutating unsafeMutableAddress {
            defer { markChanged(at: denseIndex) }
            return pointer.mutablePointer(at: denseIndex)
        }
    }

    @inlinable @inline(__always)
    public func accessDense(_ denseIndex: Int) -> SingleTypedAccess<C.QueriedComponent> {
        let tickPointer = ticks.mutablePointer(at: denseIndex)
        return SingleTypedAccess(
            buffer: pointer.mutablePointer(at: denseIndex),
            tickPointer: tickPointer,
            changeTick: changeTick
        )
    }

    @inlinable @inline(__always)
    public func access(_ id: Entity.ID) -> SingleTypedAccess<C.QueriedComponent> {
        let dense = indices[id.slot]
        let tickPointer = ticks.mutablePointer(at: dense)
        return SingleTypedAccess(
            buffer: pointer.mutablePointer(at: dense),
            tickPointer: tickPointer,
            changeTick: changeTick
        )
    }

    @inlinable @inline(__always)
    public func optionalAccess(_ id: Entity.ID) -> SingleTypedAccess<C.QueriedComponent>? {
        let index = indices[checked: id.slot]
        guard index != .notFound else {
            return nil
        }
        let tickPointer = ticks.mutablePointer(at: index)
        return SingleTypedAccess(
            buffer: pointer.mutablePointer(at: indices[id.slot]),
            tickPointer: tickPointer,
            changeTick: changeTick
        )
    }
}

extension TypedAccess {
    @inlinable @inline(__always)
    static func empty(changeTick: UInt64) -> TypedAccess {
        TypedAccess(
            pointer: SparseSet<C.QueriedComponent, SlotIndex>.DenseSpan.empty,
            indices: SlotsSpan(
                view: UnsafeMutableBufferPointer<UnsafeMutablePointer<ContiguousArray<Void>.Index>>(start: nil, count: 0)
            ),
            ticks: MutableContiguousSpan(buffer: nil, count: 0),
            changeTick: changeTick
        )
    }
}

extension TypedAccess {
    @usableFromInline @inline(__always)
    func markChanged(at denseIndex: Int) {
        ticks.mutablePointer(at: denseIndex).pointee.markChanged(at: changeTick)
    }
}

public struct SingleTypedAccess<C: Component> {
    @usableFromInline internal var buffer: UnsafeMutablePointer<C>
    @usableFromInline internal var tickPointer: UnsafeMutablePointer<ComponentTicks>
    @usableFromInline internal let changeTick: UInt64

    @inlinable @inline(__always)
    init(buffer: UnsafeMutablePointer<C>, tickPointer: UnsafeMutablePointer<ComponentTicks>, changeTick: UInt64) {
        self.buffer = buffer
        self.tickPointer = tickPointer
        self.changeTick = changeTick
    }

    @inlinable @inline(__always)
    public var value: C {
        unsafeAddress {
            UnsafePointer(buffer)
        }
        nonmutating unsafeMutableAddress {
            defer { tickPointer.pointee.markChanged(at: changeTick) }
            return buffer
        }
    }
}
