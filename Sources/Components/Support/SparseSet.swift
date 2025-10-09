public struct SparseSet<Component, SlotIndex: SparseSetIndex>: Collection, RandomAccessCollection {
    @usableFromInline
    private(set) var components: ContiguousArray<Component> = []

    /// Indexed by `SlotIndex`.
    @usableFromInline
    private(set) var slots: SparseArray<ContiguousArray.Index, SlotIndex> = []

    /// Indexed by `components`  index.
    @usableFromInline
    private(set) var keys: ContiguousArray<SlotIndex> = []

    @inlinable @inline(__always)
    public var startIndex: ContiguousArray.Index { components.startIndex }

    @inlinable @inline(__always)
    public var endIndex: ContiguousArray.Index { components.endIndex }

    @inlinable @inline(__always)
    public var indices: Range<Int> {
        0..<components.count
    }

    @inlinable @inline(__always)
    public init(_ pairs: (SlotIndex, Component)...) {
        for (id, component) in pairs {
            append(component, to: id)
        }
    }

    @inlinable @inline(__always)
    public mutating func reserveCapacity(minimumComponentCapacity: Int, minimumSlotCapacity: Int) {
        components.reserveCapacity(minimumComponentCapacity)
        keys.reserveCapacity(minimumComponentCapacity)
        slots.reserveCapacity(minimumCapacity: minimumSlotCapacity)
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

    @inlinable @inline(__always)
    public mutating func withUnsafeMutableBufferPointer<R>(
        _ body: (inout UnsafeMutableBufferPointer<Component>) throws -> R
    ) rethrows -> R {
        try components.withUnsafeMutableBufferPointer(body)
    }

    /// Returns true if this array contains a component for the given entity.
    @inlinable @inline(__always)
    public func containsEntity(_ slot: SlotIndex) -> Bool {
        /*slots.contains(index: slot) &&*/ slots[slot] != nil
    }

    @inlinable @inline(__always)
    public func componentIndex(_ slot: SlotIndex) -> ContiguousArray.Index? {
//        guard slots.contains(index: slot) else {
//            return nil
//        }
        return slots[slot]
    }

    @inlinable @inline(__always)
    mutating public func ensureEntity(_ slot: SlotIndex) {
        if !slots.contains(index: slot) {
            let missingCount = (slot.index + 1) - slots.count
            slots.append(contentsOf: repeatElement(nil, count: missingCount))
        }
    }

    @inlinable @inline(__always)
    public mutating func append(_ component: Component, to slot: SlotIndex) {
        if let index = componentIndex(slot) {
            components[index] = component
            return
        }

        components.append(component)
        keys.append(slot)
//        if !slots.contains(index: slot) {
//            let missingCount = (slot.index + 1) - slots.count
//            slots.append(contentsOf: repeatElement(nil, count: missingCount))
//        }
        slots[slot] = components.endIndex - 1
    }

    @inlinable @inline(__always)
    public mutating func remove(_ slot: SlotIndex) {
        guard /*slots.contains(index: slot),*/ let componentIndex = slots[slot] else {
            return
        }

        guard componentIndex != components.endIndex - 1 else {
            keys.removeLast()
            slots[slot] = nil
            components.removeLast()
            return
        }

        guard let lastComponentSlot = keys.popLast() else {
            fatalError("Missing entity for last component.")
        }
        components[componentIndex] = components.removeLast()
        keys[componentIndex] = lastComponentSlot
        slots[lastComponentSlot] = componentIndex
        slots[slot] = nil
    }

    @inlinable @inline(__always)
    public subscript(slot slot: SlotIndex) -> Component {
        _read {
            yield components[slots[slot]!]
        }
        _modify {
            yield &components[slots[slot]!]
        }
    }

    @inlinable @inline(__always)
    public func index(after i: ContiguousArray.Index) -> ContiguousArray.Index {
        components.index(after: i)
    }

    @inlinable @inline(__always)
    public func index(before i: ContiguousArray.Index) -> ContiguousArray.Index {
        components.index(before: i)
    }

    @inlinable @inline(__always)
    public subscript(_ position: ContiguousArray.Index) -> Component {
        _read {
            yield components[position]
        }
        _modify {
            yield &components[position]
        }
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

public struct SparseArray<Value, Index: SparseSetIndex>: Collection, ExpressibleByArrayLiteral, RandomAccessCollection {
    @usableFromInline
    private(set) var values: ContiguousArray<Value?> = []

    @inlinable @inline(__always)
    public var startIndex: Index {
        Index(index: values.startIndex)
    }

    @inlinable @inline(__always)
    public var endIndex: Index {
        Index(index: values.endIndex)
    }

    @inlinable @inline(__always)
    public init(arrayLiteral elements: Value...) {
        values = ContiguousArray(elements)
    }

    @inlinable @inline(__always)
    public func index(after i: Index) -> Index {
        Index(index: values.index(after: i.index))
    }

    @inlinable @inline(__always)
    public func index(before i: Index) -> Index {
        Index(index: values.index(before: i.index))
    }

    @inlinable @inline(__always)
    public var count: Int {
        _read {
            yield values.count
        }
    }

    @inlinable @inline(__always)
    public subscript(index: Index) -> Value? {
        _read {
            yield values[index.index]
        }
        _modify {
            yield &values[index.index]
        }
    }

    @inlinable @inline(__always)
    public func contains(index: Index) -> Bool {
        index.index < values.count
    }

    @inlinable @inline(__always)
    public mutating func append<S>(contentsOf newElements: S) where Element == S.Element, S: Sequence {
        values.append(contentsOf: newElements)
    }

    @inlinable @inline(__always)
    public mutating func reserveCapacity(minimumCapacity: Int) {
        values.reserveCapacity(minimumCapacity)
    }
}
