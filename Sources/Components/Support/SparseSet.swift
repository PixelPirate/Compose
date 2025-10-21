// TODO: Support paging for sparse array and also for dense storage.

@usableFromInline
let SparseSetInvalidDenseIndex = -1

public struct SparseSet<Component, SlotIndex: SparseSetIndex>: Collection, RandomAccessCollection {
    @usableFromInline
    private(set) var components: ContiguousArray<Component> = []

    /// Indexed by `SlotIndex`.
    @usableFromInline
    private(set) var slots: ContiguousArray<Int> = []

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
        slots.reserveCapacity(minimumSlotCapacity)
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
        let raw = slot.index
        return raw < slots.count && slots[raw] != SparseSetInvalidDenseIndex
    }

    @inlinable @inline(__always)
    public func componentIndex(_ slot: SlotIndex) -> ContiguousArray.Index? {
        let raw = slot.index
        guard raw < slots.count else {
            return nil
        }
        let dense = slots[raw]
        return dense == SparseSetInvalidDenseIndex ? nil : dense
    }

    @inlinable @inline(__always)
    mutating public func ensureEntity(_ slot: SlotIndex) {
        if slot.index >= slots.count {
            let missingCount = (slot.index + 1) - slots.count
            slots.append(contentsOf: repeatElement(SparseSetInvalidDenseIndex, count: missingCount))
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
        if slot.index >= slots.count {
            let missingCount = (slot.index + 1) - slots.count
            slots.append(contentsOf: repeatElement(SparseSetInvalidDenseIndex, count: missingCount))
        }
        slots[slot.index] = components.endIndex - 1
    }

    @inlinable @inline(__always)
    public mutating func remove(_ slot: SlotIndex) {
        guard let componentIndex = componentIndex(slot) else {
            return
        }

        guard componentIndex != components.endIndex - 1 else {
            keys.removeLast()
            slots[slot.index] = SparseSetInvalidDenseIndex
            components.removeLast()
            return
        }

        guard let lastComponentSlot = keys.popLast() else {
            fatalError("Missing entity for last component.")
        }
        components[componentIndex] = components.removeLast()
        keys[componentIndex] = lastComponentSlot
        slots[lastComponentSlot.index] = componentIndex
        slots[slot.index] = SparseSetInvalidDenseIndex
    }

    /// Swap two elements in the dense storage and fix up the index maps.
    /// - Precondition: i and j are valid dense indices into `components`.
    @inlinable @inline(__always)
    internal mutating func swapDenseAt(_ i: ContiguousArray.Index, _ j: ContiguousArray.Index) {
        if i == j { return }
        components.swapAt(i, j)
        // keys[i] / keys[j] are SlotIndex that correspond to the entities at those dense positions.
        let ki = keys[i]
        let kj = keys[j]
        keys.swapAt(i, j)
        // Update sparse map so that the slots now point to the new dense indices.
        slots[ki.index] = j
        slots[kj.index] = i
    }

    @inlinable @inline(__always)
    public subscript(slot slot: SlotIndex) -> Component {
        _read {
            yield components[slots[slot.index]]
        }
        _modify {
            yield &components[slots[slot.index]]
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

