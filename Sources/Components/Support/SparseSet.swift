public struct SparseSet<Component, SlotIndex: SparseSetIndex>: Collection, RandomAccessCollection {
    @usableFromInline
    private(set) var components: PagedArray<Component> = []

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
        components.reserveCapacity(minimumCapacity: minimumComponentCapacity)
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

    @available(*, unavailable, message: "SparseSet storage is paged; use withPagedStorage APIs instead.")
    @inlinable @inline(__always)
    public mutating func withUnsafeMutableBufferPointer<R>(
        _ body: (inout UnsafeMutableBufferPointer<Component>) throws -> R
    ) rethrows -> R {
        fatalError("SparseSet.withUnsafeMutableBufferPointer is unavailable for paged storage.")
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
        if !slots.contains(index: slot) {
            let missingCount = (slot.index + 1) - slots.count
            slots.append(contentsOf: repeatElement(.notFound, count: missingCount))
        }
    }

    @inlinable @inline(__always)
    public mutating func append(_ component: Component, to slot: SlotIndex) {
        let index = componentIndex(slot)
        if index != .notFound {
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
        let componentIndex = slots[slot]
//        guard /*slots.contains(index: slot),*/ let componentIndex = slots[slot] else {
//            return
//        }

        guard componentIndex != .notFound else {
            return
        }

        guard componentIndex != components.endIndex - 1 else {
            keys.removeLast()
            slots[slot] = .notFound
            components.removeLast()
            return
        }

        guard let lastComponentSlot = keys.popLast() else {
            fatalError("Missing entity for last component.")
        }
        components[componentIndex] = components.removeLast()
        keys[componentIndex] = lastComponentSlot
        slots[lastComponentSlot] = componentIndex
        slots[slot] = .notFound
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
        slots[ki] = j
        slots[kj] = i
    }

    @inlinable @inline(__always)
    public subscript(slot slot: SlotIndex) -> Component {
        _read {
            yield components[slots[slot]]
        }
        _modify {
            yield &components[slots[slot]]
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

@usableFromInline
struct PagedArray<Element>: RandomAccessCollection, MutableCollection, ExpressibleByArrayLiteral {
    typealias Index = Int

    @usableFromInline
    static let pageShift = 12

    @usableFromInline
    static let pageSize = 1 << pageShift

    @usableFromInline
    static let pageMask = pageSize - 1

    @usableFromInline
    var pages: [ContiguousArray<Element>] = []

    @usableFromInline
    private(set) var countStorage: Int = 0

    @inlinable @inline(__always)
    init() {}

    @inlinable @inline(__always)
    init(arrayLiteral elements: Element...) {
        self.init()
        append(contentsOf: elements)
    }

    @inlinable @inline(__always)
    init<S: Sequence>(_ elements: S) where S.Element == Element {
        self.init()
        append(contentsOf: elements)
    }

    @inlinable @inline(__always)
    var startIndex: Int { 0 }

    @inlinable @inline(__always)
    var endIndex: Int { countStorage }

    @inlinable @inline(__always)
    var count: Int { countStorage }

    @inlinable @inline(__always)
    var indices: Range<Int> { 0..<count }

    @inlinable @inline(__always)
    mutating func reserveCapacity(minimumCapacity: Int) {
        let requiredPages = (minimumCapacity + Self.pageMask) >> Self.pageShift
        pages.reserveCapacity(requiredPages)
        for index in pages.indices {
            pages[index].reserveCapacity(Self.pageSize)
        }
    }

    @inlinable @inline(__always)
    mutating func append(_ newElement: Element) {
        let pageIndex = countStorage >> Self.pageShift
        if pageIndex == pages.count {
            pages.append(ContiguousArray<Element>())
            pages[pageIndex].reserveCapacity(Self.pageSize)
        }
        pages[pageIndex].append(newElement)
        countStorage += 1
    }

    @inlinable @inline(__always)
    mutating func append<S: Sequence>(contentsOf newElements: S) where S.Element == Element {
        for element in newElements {
            append(element)
        }
    }

    @inlinable @inline(__always)
    @discardableResult
    mutating func popLast() -> Element? {
        guard !isEmpty else { return nil }
        return removeLast()
    }

    @inlinable @inline(__always)
    @discardableResult
    mutating func removeLast() -> Element {
        precondition(!isEmpty, "Cannot removeLast from empty PagedArray")
        let index = countStorage - 1
        countStorage -= 1
        let pageIndex = index >> Self.pageShift
        let value = pages[pageIndex].removeLast()
        if pages[pageIndex].isEmpty {
            pages.removeLast()
        }
        return value
    }

    @inlinable @inline(__always)
    mutating func swapAt(_ i: Int, _ j: Int) {
        if i == j { return }
        let (pageI, offsetI) = pageAndOffset(for: i)
        let (pageJ, offsetJ) = pageAndOffset(for: j)
        pages[pageI].swapAt(offsetI, offsetJ)
    }

    @inlinable @inline(__always)
    func index(after i: Int) -> Int { i + 1 }

    @inlinable @inline(__always)
    func index(before i: Int) -> Int { i - 1 }

    @inlinable @inline(__always)
    subscript(position: Int) -> Element {
        _read {
            let (page, offset) = pageAndOffset(for: position)
            yield pages[page][offset]
        }
        _modify {
            let (page, offset) = pageAndOffset(for: position)
            yield &pages[page][offset]
        }
    }

    @available(*, unavailable, message: "PagedArray storage is paged; use page-wise APIs instead.")
    @inlinable @inline(__always)
    mutating func withUnsafeMutableBufferPointer<R>(
        _ body: (inout UnsafeMutableBufferPointer<Element>) throws -> R
    ) rethrows -> R {
        fatalError("PagedArray.withUnsafeMutableBufferPointer is unavailable for paged storage.")
    }

    @usableFromInline
    func pageAndOffset(for position: Int) -> (Int, Int) {
        precondition(position >= 0 && position < countStorage, "Index out of bounds")
        let page = position >> Self.pageShift
        let offset = position & Self.pageMask
        return (page, offset)
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
    @usableFromInline
    private(set) var values: PagedArray<Value> = []

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
        values = PagedArray(elements)
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
    public subscript(index: Index) -> Value {
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
