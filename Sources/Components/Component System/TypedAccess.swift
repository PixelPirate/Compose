public struct TypedAccess<C: ComponentResolving>: @unchecked Sendable {
    @usableFromInline internal var pointer: SparseSet<C.QueriedComponent, SlotIndex>.DenseSpan
    @usableFromInline internal var indices: SlotsSpan<ContiguousArray.Index, SlotIndex>
    @usableFromInline internal var ticks: ContiguousSpan<ComponentTicks>?
    @usableFromInline internal let changeTick: UInt64
    @usableFromInline internal let tag: ComponentTag

    @usableFromInline
    init(
        pointer: SparseSet<C.QueriedComponent, SlotIndex>.DenseSpan,
        indices: SlotsSpan<ContiguousArray.Index, SlotIndex>,
        ticks: ContiguousSpan<ComponentTicks>?,
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
        _read {
            yield pointer[indices[id.slot]]
        }
        nonmutating _modify {
            let dense = indices[id.slot]
            defer { markChanged(at: dense) }
            yield &pointer[dense]
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
        _read { yield pointer[denseIndex] }
        nonmutating _modify {
            defer { markChanged(at: denseIndex) }
            yield &pointer[denseIndex]
        }
    }

    @inlinable @inline(__always)
    public func accessDense(_ denseIndex: Int) -> SingleTypedAccess<C.QueriedComponent> {
        let tickPointer = ticks?.mutablePointer(at: denseIndex)
        return SingleTypedAccess(
            buffer: pointer.mutablePointer(at: denseIndex),
            tickPointer: tickPointer,
            changeTick: changeTick
        )
    }

    @inlinable @inline(__always)
    public func access(_ id: Entity.ID) -> SingleTypedAccess<C.QueriedComponent> {
        let dense = indices[id.slot]
        let tickPointer = ticks?.mutablePointer(at: dense)
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
        let tickPointer = ticks?.mutablePointer(at: index)
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
            pointer: SparseSet<C.QueriedComponent, SlotIndex>.DenseSpan(),
            indices: SlotsSpan(
                view: UnsafeMutableBufferPointer<UnsafeMutablePointer<ContiguousArray<Void>.Index>>(start: nil, count: 0)
            ),
            ticks: nil,
            changeTick: changeTick
        )
    }
}

extension TypedAccess {
    @usableFromInline @inline(__always)
    func markChanged(at denseIndex: Int) {
        guard let ticks else { return }
        ticks.mutablePointer(at: denseIndex).pointee.markChanged(at: changeTick)
    }
}

public struct SingleTypedAccess<C: Component> {
    @usableFromInline internal var buffer: UnsafeMutablePointer<C>
    @usableFromInline internal var tickPointer: UnsafeMutablePointer<ComponentTicks>?
    @usableFromInline internal let changeTick: UInt64

    @inlinable @inline(__always)
    init(buffer: UnsafeMutablePointer<C>, tickPointer: UnsafeMutablePointer<ComponentTicks>?, changeTick: UInt64) {
        self.buffer = buffer
        self.tickPointer = tickPointer
        self.changeTick = changeTick
    }

    @inlinable @inline(__always)
    public var value: C {
        _read {
            yield buffer.pointee
        }
        nonmutating _modify {
            defer { tickPointer?.pointee.markChanged(at: changeTick) }
            yield &buffer.pointee
        }
    }
}
