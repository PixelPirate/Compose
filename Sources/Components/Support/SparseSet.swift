public struct SparseSet<Component, SlotIndex: SparseSetIndex>: Collection, RandomAccessCollection {
    public struct DenseSpan {
        @usableFromInline
        let span: ContiguousDense<Component>.Span

        @usableFromInline @_transparent
        init(span: ContiguousDense<Component>.Span) {
            self.span = span
        }

        @usableFromInline @_transparent
        init() {
            self.span = ContiguousDense<Component>.Span(view: UnsafeMutableBufferPointer<Component>(start: nil, count: 0), count: 0)
        }

        @inlinable @_transparent
        public func mutablePointer(at index: Int) -> UnsafeMutablePointer<Element> {
            span.mutablePointer(at: index)
        }

        @inlinable @inline(__always)
        public subscript(index: Int) -> Element {
            @_transparent
            unsafeAddress {
                UnsafePointer(span.mutablePointer(at: index))
            }

            @_transparent
            nonmutating unsafeMutableAddress {
                span.mutablePointer(at: index)
            }
        }
    }

//    @usableFromInline
//    private(set) var storage: ContiguousStorage<Component> = ContiguousStorage(initialPageCapacity: 1024)
    @usableFromInline
    private(set) var storage: ContiguousDense<Component> = ContiguousDense()

    /// Indexed by `SlotIndex`.
    @usableFromInline
    private(set) var slots: SparseArray<ContiguousArray.Index, SlotIndex> = []

    /// Indexed by `components`  index.
    @usableFromInline
    private(set) var keys: ContiguousDense<SlotIndex> = ContiguousDense()

    @inlinable @inline(__always)
    public var startIndex: ContiguousArray.Index { 0 }

    @inlinable @inline(__always)
    public var endIndex: ContiguousArray.Index { storage.count }

    @inlinable @inline(__always)
    public var indices: Range<Int> {
        Range(uncheckedBounds: (0, storage.count))
    }

    @inlinable @inline(__always)
    public init(_ pairs: (SlotIndex, Component)...) {
        for (id, component) in pairs {
            append(component, to: id)
        }
    }

    @inlinable @inline(__always)
    public mutating func reserveCapacity(minimumComponentCapacity: Int, minimumSlotCapacity: Int) {
//        components.reserveCapacity(minimumComponentCapacity)
        keys.ensureCapacity(minimumComponentCapacity)
        slots.ensureCapacity(forIndex: SlotIndex(index: minimumSlotCapacity - 1))
    }

    @inlinable @inline(__always)
    public init(_ pairs: [(SlotIndex, Component)]) {
        for (id, component) in pairs {
            append(component, to: id)
        }
    }

    @inlinable @inline(__always)
    public init(_ pairs: (Array.Index, Component)...) where SlotIndex == Array.Index {
        for (id, component) in pairs {
            append(component, to: id)
        }
    }

    @inlinable @inline(__always)
    public init(_ pairs: [(Array.Index, Component)]) where SlotIndex == Array.Index {
        for (id, component) in pairs {
            append(component, to: id)
        }
    }

//    @inlinable @inline(__always)
//    public mutating func withUnmanagedStorage<R>(
//        _ body: (UnmanagedContiguousStorage<Component>) throws -> R
//    ) rethrows -> R {
//        try body(UnmanagedContiguousStorage(storage))
//    }
//
//    @inlinable @inline(__always)
//    public mutating func withUnsafeMutablePointer<R>(
//        _ body: (UnsafeMutablePointer<Component>) throws -> R
//    ) rethrows -> R {
//        try body(storage.baseAddress)
//    }

    @inlinable @_transparent
    public var view: DenseSpan {
        _read {
            yield DenseSpan(span: storage.view)
        }
    }

    /// Returns true if this array contains a component for the given entity.
    @inlinable @inline(__always)
    public func containsEntity(_ slot: SlotIndex) -> Bool {
        slots[slot] != .notFound
    }

    @inlinable @inline(__always)
    public func componentIndex(_ slot: SlotIndex) -> ContiguousArray.Index {
        slots[slot]
    }

    @inlinable @inline(__always)
    mutating public func ensureEntity(_ slot: SlotIndex) {
        slots.ensureCapacity(forIndex: slot)
    }

    @inlinable @inline(__always)
    public mutating func append(_ component: Component, to slot: SlotIndex) {
        precondition(componentIndex(slot) == .notFound)
        storage.append(component)
        keys.append(slot)
        slots[slot] = storage.count - 1
    }

    @inlinable @inline(__always) @discardableResult
    public mutating func remove(_ slot: SlotIndex) -> (component: Component, denseIndex: Int)? {
        let componentIndex = slots[slot]
        guard componentIndex != .notFound else {
            return nil
        }

        guard componentIndex != storage.count - 1 else {
            keys.removeLast()
            slots[slot] = .notFound
            return (component: storage.removeLast(), denseIndex: componentIndex)
        }

        guard let lastComponentSlot = keys.popLast() else {
            fatalError("Missing entity for last component.")
        }
        let old = storage[componentIndex]
        storage[componentIndex] = storage.removeLast()
        keys[componentIndex] = lastComponentSlot
        slots[lastComponentSlot] = componentIndex
        slots[slot] = .notFound
        return (component: old, componentIndex)
    }

    @inlinable @inline(__always) @discardableResult
    public mutating func partition(by belongsInSecondPartition: (SlotIndex) -> Bool) -> Int {
        let total = count
        var write = 0
        var read = 0
        while read < total {
            let slot = keys[read]
            if !belongsInSecondPartition(slot) {
                if read != write {
                    swapDenseAt(read, write)
                }
                write &+= 1
            }
            read &+= 1
        }
        return write
    }

    /// Swap two elements in the dense storage and fix up the index maps.
    /// - Precondition: i and j are valid dense indices into `components`.
    @inlinable @inline(__always)
    internal mutating func swapDenseAt(_ i: ContiguousArray.Index, _ j: ContiguousArray.Index) {
        if i == j { return }
        storage.swapAt(i, j)
        // keys[i] / keys[j] are SlotIndex that correspond to the entities at those dense positions.
        let ki = keys[i]
        let kj = keys[j]
        keys.swapAt(i, j)
        // Update sparse map so that the slots now point to the new dense indices.
        slots[ki] = j
        slots[kj] = i
    }

    @inlinable @inline(__always)
    public subscript(slot slot: SlotIndex) -> Component {
        _read {
            yield storage[slots[slot]]
        }
        _modify {
            yield &storage[slots[slot]]
        }
    }

    @inlinable @inline(__always)
    public func index(after i: ContiguousArray.Index) -> ContiguousArray.Index {
        i + 1
    }

    @inlinable @inline(__always)
    public func index(before i: ContiguousArray.Index) -> ContiguousArray.Index {
        i - 1
    }

    @inlinable @inline(__always)
    public subscript(_ position: ContiguousArray.Index) -> Component {
        _read {
            yield storage[position]
        }
        _modify {
            yield &storage[position]
        }
    }

    @inlinable @inline(__always)
    public var slotPages: Int {
        slots.values.pages.count
    }

    @inlinable @inline(__always)
    public var liveSlotPages: Int {
        slots.values.liveCount
    }
}

public protocol SparseSetIndex: Hashable, Comparable {
    @inlinable @inline(__always)
    var index: Array.Index { get }

    @inlinable @inline(__always)
    init(index: Array.Index)
}

extension Array.Index: SparseSetIndex {
    @inlinable @inline(__always)
    public var index: Array.Index {
        self
    }

    @inlinable @inline(__always)
    public init(index: Array.Index) {
        self = index
    }
}

extension ContiguousArray.Index: SparseArrayValue {
    @inline(__always)
    public static let notFound: Array.Index = -1
}

public protocol SparseArrayValue: Hashable, Comparable {
    @inlinable @inline(__always)
    var index: Array.Index { get }

    @inlinable @inline(__always)
    static var notFound: Self { get }

    @inlinable @inline(__always)
    init(index: Array.Index)
}

public struct SparseArray<Value: SparseArrayValue, Index: SparseSetIndex>: Collection, ExpressibleByArrayLiteral, RandomAccessCollection {
    @usableFromInline
    private(set) var values: PagedSlotToDense<Value, Index> = PagedSlotToDense()

    @inlinable @inline(__always)
    public var startIndex: Index {
        Index(index: 0)
    }

    @inlinable @inline(__always)
    public var endIndex: Index {
        Index(index: values.count)
    }

    @inlinable @inline(__always)
    public init(arrayLiteral elements: Value...) {
        var index = 0
        for element in elements {
            values[Index(index: index)] = element
            index += 1
        }
    }

    @inlinable @inline(__always)
    public func index(after i: Index) -> Index {
        Index(index: i.index + 1)
    }

    @inlinable @inline(__always)
    public func index(before i: Index) -> Index {
        Index(index: i.index - 1)
    }

    @inlinable @inline(__always)
    public var count: Int {
        _read {
            yield values.count
        }
    }

    @inlinable @inline(__always)
    public subscript(index: Index) -> Value {
        @_transparent
        unsafeAddress {
            values.pointer(for: index)
        }

        @_transparent
        mutating _modify {
            yield &values[index]
        }
    }

    @inlinable @inline(__always)
    public mutating func append<S>(contentsOf newElements: S) where Element == S.Element, S: Sequence {
        var next = count
        for element in newElements {
            self[Index(index: next)] = element
            next += 1
        }
    }

    @inlinable @_transparent
    public var view: SlotsSpan<Value, Index> {
        @_transparent
        _read {
            yield values.view
        }
    }

    @inlinable @inline(__always)
    public mutating func ensureCapacity(forIndex index: Index) {
        values.ensureCapacity(forSlot: index)
    }
}
