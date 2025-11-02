@usableFromInline
struct ComponentMutationContext {
    @usableFromInline
    nonisolated(unsafe) let coordinator: Coordinator

    @usableFromInline
    let componentTag: ComponentTag

    @usableFromInline
    let slot: SlotIndex

    @usableFromInline
    init(coordinator: Coordinator, componentTag: ComponentTag, slot: SlotIndex) {
        self.coordinator = coordinator
        self.componentTag = componentTag
        self.slot = slot
    }

    @inlinable @inline(__always)
    func markChanged() {
        coordinator.markComponentMutated(componentTag, slot: slot)
    }
}

@usableFromInline
struct ComponentMutationObserver {
    @usableFromInline
    nonisolated(unsafe) let coordinator: Coordinator

    @usableFromInline
    let componentTag: ComponentTag

    @inlinable @inline(__always)
    func makeContext(slot: SlotIndex) -> ComponentMutationContext {
        ComponentMutationContext(coordinator: coordinator, componentTag: componentTag, slot: slot)
    }
}

public struct TypedAccess<C: ComponentResolving>: @unchecked Sendable {
    @usableFromInline internal var pointer: DenseSpan2<C.QueriedComponent>
    @usableFromInline internal var indices: SlotsSpan<ContiguousArray.Index, SlotIndex>
    @usableFromInline internal var mutationObserver: ComponentMutationObserver?

    @usableFromInline
    init(
        pointer: DenseSpan2<C.QueriedComponent>,
        indices: SlotsSpan<ContiguousArray.Index, SlotIndex>,
        mutationObserver: ComponentMutationObserver?
    ) {
        self.pointer = pointer
        self.indices = indices
        self.mutationObserver = mutationObserver
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
    public func access(_ id: Entity.ID) -> SingleTypedAccess<C.QueriedComponent> {
        let context = mutationObserver?.makeContext(slot: id.slot)
        return SingleTypedAccess(buffer: pointer.mutablePointer(at: indices[id.slot]), mutationContext: context)
    }

    @inlinable @inline(__always)
    public func optionalAccess(_ id: Entity.ID) -> SingleTypedAccess<C.QueriedComponent>? {
        let index = indices[checked: id.slot]
        guard index != .notFound else {
            return nil
        }
        let context = mutationObserver?.makeContext(slot: id.slot)
        return SingleTypedAccess(buffer: pointer.mutablePointer(at: indices[id.slot]), mutationContext: context)
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
            mutationObserver: nil
        )
    }
}

public struct SingleTypedAccess<C: Component> {
    @usableFromInline internal var buffer: UnsafeMutablePointer<C>
    @usableFromInline internal var mutationContext: ComponentMutationContext?

    @inlinable @inline(__always)
    init(buffer: UnsafeMutablePointer<C>, mutationContext: ComponentMutationContext?) {
        self.buffer = buffer
        self.mutationContext = mutationContext
    }

    @inlinable @inline(__always)
    public var value: C {
        _read {
            yield buffer.pointee
        }
        nonmutating set {
            buffer.pointee = newValue
            mutationContext?.markChanged()
        }
        nonmutating _modify {
            defer { mutationContext?.markChanged() }
            yield &buffer.pointee
        }
    }
}
