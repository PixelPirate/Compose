//
//  TypedAccess.swift
//  Components
//
//  Created by Patrick Horlebein (extern) on 10.10.25.
//

public struct TypedAccess<C: ComponentResolving>: @unchecked Sendable {
    @usableFromInline internal var storage: UnmanagedStorage<C.QueriedComponent>
    @usableFromInline internal var indices: ContiguousArray<ContiguousArray.Index>

    @usableFromInline
    init(storage: UnmanagedStorage<C.QueriedComponent>, indices: ContiguousArray<ContiguousArray.Index>) {
        self.storage = storage
        self.indices = indices
    }

    @inlinable @inline(__always)
    public subscript(_ id: Entity.ID) -> C.QueriedComponent {
        _read {
            yield storage[indices[id.slot.rawValue]]
        }
        nonmutating _modify {
            yield &storage[indices[id.slot.rawValue]]
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
            yield storage[index]
        }
        nonmutating _modify {
            var wrapped: Optional<C.QueriedComponent>
            let index = indices[id.slot.rawValue]
            if index != .notFound {
                wrapped = Optional(storage[index])
                yield &wrapped
                guard let newValue = wrapped else {
                    fatalError("Removal of component through `Optional` not supported.")
                }
                storage[index] = newValue
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
        _read { yield storage[denseIndex] }
        nonmutating _modify { yield &storage[denseIndex] }
    }

    @inlinable @inline(__always)
    public func accessDense(_ denseIndex: Int) -> SingleTypedAccess<C.QueriedComponent> {
        SingleTypedAccess(buffer: storage.elementPointer(denseIndex))
    }

    @inlinable @inline(__always)
    public func access(_ id: Entity.ID) -> SingleTypedAccess<C.QueriedComponent> {
        SingleTypedAccess(buffer: storage.elementPointer(indices[id.slot.rawValue]))
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
        return SingleTypedAccess(buffer: storage.elementPointer(indices[id.slot.rawValue]))
    }
}

extension TypedAccess {
    @inlinable @inline(__always)
    static var empty: TypedAccess {
        // a harmless instance that never resolves anything
        TypedAccess(
            storage: UnmanagedStorage(
                .passRetained(PagesBuffer<C.QueriedComponent>.create(initialCapacity: 1)),
                count: 0,
                pageCount: 0
            ),
            indices: []
        )
    }

    @inlinable @inline(__always)
    public func denseCursor() -> DenseStorageCursor<C.QueriedComponent> {
        DenseStorageCursor(storage: storage)
    }
}

extension DenseStorageCursor {
    var pointer: UnsafeMutablePointer<Self> {
        mutating get {
            withUnsafeMutablePointer(to: &self) { pointer in
                pointer
            }
        }
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

public struct DenseStorageCursor<Component> {
    @usableFromInline
    let pages: Unmanaged<PagesBuffer<Component>>
    @usableFromInline
    let pageCount: Int
    @usableFromInline
    let count: Int

    @usableFromInline
    var cachedPageIndex: Int = -1
    @usableFromInline
    var cachedElements: UnsafeMutablePointer<Component>? = nil

    @inlinable @inline(__always)
    init(storage: UnmanagedStorage<Component>) {
        self.pages = storage.pages
        self.pageCount = storage.pageCount
        self.count = storage.count
    }

    @inlinable @inline(__always)
    public mutating func pointer(forDenseIndex denseIndex: Int) -> UnsafeMutablePointer<Component> {
        precondition(denseIndex < count)
        let pageIndex = denseIndex >> pageShift
        precondition(pageIndex < pageCount)
        let offset = denseIndex & pageMask

        if pageIndex != cachedPageIndex {
            cachedElements = pages._withUnsafeGuaranteedRef { buffer in
                buffer.withUnsafeMutablePointerToElements { pagesPointer in
                    pagesPointer
                        .advanced(by: pageIndex)
                        .pointee
                        .withUnsafeMutablePointerToElements { $0 }
                }
            }
            cachedPageIndex = pageIndex
        }

        return cachedElements!.advanced(by: offset)
    }
}
