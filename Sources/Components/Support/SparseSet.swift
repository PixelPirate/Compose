// TODO: Support paging for sparse array and also for dense storage.

public struct SparseSet<Component, SlotIndex: SparseSetIndex>: Collection, RandomAccessCollection {
    @usableFromInline
    private(set) var storage: ContiguousStorage<Component> = ContiguousStorage(initialPageCapacity: 1024)

    /// Indexed by `SlotIndex`.
    @usableFromInline
    private(set) var slots: SparseArray<ContiguousArray.Index, SlotIndex> = []

    /// Indexed by `components`  index.
    @usableFromInline
    private(set) var keys: ContiguousArray<SlotIndex> = []

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
    public mutating func withUnmanagedStorage<R>(
        _ body: (UnmanagedContiguousStorage<Component>) throws -> R
    ) rethrows -> R {
        try body(UnmanagedContiguousStorage(storage))
    }

    @inlinable @inline(__always)
    public mutating func withUnsafeMutablePointer<R>(
        _ body: (UnsafeMutablePointer<Component>) throws -> R
    ) rethrows -> R {
        try body(storage.baseAddress)
    }

    /// Returns true if this array contains a component for the given entity.
    @inlinable @inline(__always)
    public func containsEntity(_ slot: SlotIndex) -> Bool {
        /*slots.contains(index: slot) &&*/ slots[slot] != .notFound
    }

    @inlinable @inline(__always)
    public func componentIndex(_ slot: SlotIndex) -> ContiguousArray.Index {
//        guard slots.contains(index: slot) else {
//            return nil
//        }
        return slots[slot]
    }

    @inlinable @inline(__always)
    mutating public func ensureEntity(_ slot: SlotIndex) {
        // Capacity is now grown on demand when assigning values.
    }

    @inlinable @inline(__always)
    public mutating func append(_ component: Component, to slot: SlotIndex) {
        let index = componentIndex(slot)
        if index != .notFound {
            storage[index] = component
            return
        }

        storage.append(component)
        keys.append(slot)
//        if !slots.contains(index: slot) {
//            let missingCount = (slot.index + 1) - slots.count
//            slots.append(contentsOf: repeatElement(nil, count: missingCount))
//        }
        slots[slot] = storage.count - 1
    }

    @inlinable @inline(__always)
    public mutating func remove(_ slot: SlotIndex) {
        let componentIndex = slots[slot]
//        guard /*slots.contains(index: slot),*/ let componentIndex = slots[slot] else {
//            return
//        }

        guard componentIndex != .notFound else {
            return
        }

        guard componentIndex != storage.count - 1 else {
            keys.removeLast()
            slots[slot] = .notFound
            storage.removeLast()
            return
        }

        guard let lastComponentSlot = keys.popLast() else {
            fatalError("Missing entity for last component.")
        }
        storage[componentIndex] = storage.removeLast()
        keys[componentIndex] = lastComponentSlot
        slots[lastComponentSlot] = componentIndex
        slots[slot] = .notFound
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
    static var notFound: Array.Index { get }

    @inlinable @inline(__always)
    init(index: Array.Index)
}

public struct SparseArray<Value: SparseArrayValue, Index: SparseSetIndex>: Collection, ExpressibleByArrayLiteral, RandomAccessCollection {
//    @usableFromInline
//    private(set) var values: ContiguousArray<Value> = [] // TODO: This needs to be paged.
    @usableFromInline
    private(set) var values: PagedStorage<Value> = PagedStorage(initialPageCapacity: 4096)
    @usableFromInline
    var pageOccupancy: [Int: Int] = [:]

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
        values = PagedStorage()
        pageOccupancy = [:]
        var index = 0
        for element in elements {
            self[Index(index: index)] = element
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
        get {
            let raw = index.index
            guard raw < values.count else { return .notFound }
            let pageIndex = raw >> pageShift
            guard let page = values.page(at: pageIndex) else { return .notFound }
            let offset = raw & pageMask
            return page.value(at: offset)
        }
        set {
            let raw = index.index
            let pageIndex = raw >> pageShift
            let offset = raw & pageMask

            if newValue == .notFound {
                guard let page = values.page(at: pageIndex) else { return }
                page.withUnsafeMutablePointerToElements { pointer in
                    let slot = pointer.advanced(by: offset)
                    if slot.pointee == .notFound {
                        return
                    }
                    slot.pointee = .notFound
                }
                if let current = pageOccupancy[pageIndex] {
                    if current <= 1 {
                        pageOccupancy.removeValue(forKey: pageIndex)
                        values.removePage(at: pageIndex)
                    } else {
                        pageOccupancy[pageIndex] = current - 1
                    }
                }
                values.shrinkTrailingNilPages()
                return
            }

            var page = values.page(at: pageIndex)
            if page == nil {
                page = values.ensurePage(forPage: pageIndex)
                page!.withUnsafeMutablePointerToElements { pointer in
                    pointer.initialize(repeating: .notFound, count: pageCapacity)
                }
                pageOccupancy[pageIndex] = 0
            }
            guard let existingPage = page else { return }
            existingPage.withUnsafeMutablePointerToElements { pointer in
                let slot = pointer.advanced(by: offset)
                if slot.pointee == .notFound {
                    pageOccupancy[pageIndex, default: 0] += 1
                }
                slot.pointee = newValue
            }
            values.updateCountForPageIndex(pageIndex)
        }
    }

    @inlinable @inline(__always)
    public func contains(index: Index) -> Bool {
        let raw = index.index
        guard raw < values.count else { return false }
        let pageIndex = raw >> pageShift
        return values.page(at: pageIndex) != nil
    }

    @inlinable @inline(__always)
    public mutating func append<S>(contentsOf newElements: S) where Element == S.Element, S: Sequence {
//        values.append(contentsOf: newElements)
        var next = count
        for element in newElements {
            self[Index(index: next)] = element
            next += 1
        }
    }

    @inlinable @inline(__always)
    public mutating func reserveCapacity(minimumCapacity: Int) {
//        values.reserveCapacity(minimumCapacity)
    }
}
