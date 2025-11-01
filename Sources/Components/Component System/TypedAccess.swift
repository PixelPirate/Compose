public struct TypedAccess<C: ComponentResolving>: @unchecked Sendable {
    @usableFromInline internal var pointer: DenseSpan2<C.QueriedComponent>
    @usableFromInline internal var indices: SlotsSpan<ContiguousArray.Index, SlotIndex>
    @usableFromInline internal var changeContext: ComponentChangeObserverContext?

    @usableFromInline
    init(
        pointer: DenseSpan2<C.QueriedComponent>,
        indices: SlotsSpan<ContiguousArray.Index, SlotIndex>,
        changeContext: ComponentChangeObserverContext? = nil
    ) {
        self.pointer = pointer
        self.indices = indices
        self.changeContext = changeContext
    }

    @inlinable @inline(__always)
    public subscript(_ id: Entity.ID) -> C.QueriedComponent {
        _read {
            yield pointer[indices[id.slot]]
        }
        nonmutating _modify {
            yield &pointer[indices[id.slot]]
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
    public func accessDense(_ denseIndex: Int, entityID: Entity.ID) -> SingleTypedAccess<C.QueriedComponent> {
        SingleTypedAccess(
            buffer: pointer.mutablePointer(at: denseIndex),
            observer: changeContext?.observer(for: entityID)
        )
    }

    @inlinable @inline(__always)
    public func access(_ id: Entity.ID) -> SingleTypedAccess<C.QueriedComponent> {
        SingleTypedAccess(
            buffer: pointer.mutablePointer(at: indices[id.slot]),
            observer: changeContext?.observer(for: id)
        )
    }

    @inlinable @inline(__always)
    public func optionalAccess(_ id: Entity.ID) -> SingleTypedAccess<C.QueriedComponent>? {
        let index = indices[checked: id.slot]
        guard index != .notFound else {
            return nil
        }
        return SingleTypedAccess(
            buffer: pointer.mutablePointer(at: indices[id.slot]),
            observer: changeContext?.observer(for: id)
        )
    }
}

extension TypedAccess {
    @inlinable @inline(__always)
    static var empty: TypedAccess {
        TypedAccess(
            pointer: DenseSpan2(
                view: UnsafeMutableBufferPointer<C.QueriedComponent>(start: nil, count: 0)
            ),
            indices: SlotsSpan(
                view: UnsafeMutableBufferPointer<UnsafeMutablePointer<ContiguousArray<Void>.Index>>(start: nil, count: 0)
            ),
            changeContext: nil
        )
    }
}

public struct SingleTypedAccess<C: Component> {
    @usableFromInline internal var buffer: UnsafeMutablePointer<C>
    @usableFromInline internal let changeObserver: ComponentChangeObserver?

    @inlinable @inline(__always)
    init(buffer: UnsafeMutablePointer<C>, observer: ComponentChangeObserver? = nil) {
        self.buffer = buffer
        self.changeObserver = observer
    }

    @inlinable @inline(__always)
    public var value: C {
        _read {
            yield buffer.pointee
        }
        nonmutating _modify {
            let observer = changeObserver
            yield &buffer.pointee
            observer?.markChanged()
        }
        nonmutating set {
            buffer.pointee = newValue
            changeObserver?.markChanged()
        }
    }
}
