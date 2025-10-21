// TODO: Support paging for sparse array and also for dense storage.

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
        slots.ensureCapacity(for: slot)
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
    public typealias ArrayLiteralElement = Value
    @usableFromInline
    final class Storage {
        @usableFromInline
        var pages: ContiguousArray<ContiguousArray<Value>?>

        @usableFromInline
        var logicalCount: Int

        @usableFromInline
        init(pages: ContiguousArray<ContiguousArray<Value>?> = [], logicalCount: Int = 0) {
            self.pages = pages
            self.logicalCount = logicalCount
        }

        @usableFromInline
        func copy() -> Storage {
            Storage(pages: pages, logicalCount: logicalCount)
        }

        @usableFromInline
        func value(at rawIndex: Int) -> Value {
            guard rawIndex < logicalCount else {
                return Value(index: Value.notFound)
            }
            let pageIndex = rawIndex >> SparseArray<Value, Index>.pageShift
            guard pageIndex < pages.count, let page = pages[pageIndex] else {
                return Value(index: Value.notFound)
            }
            return page[rawIndex & SparseArray<Value, Index>.pageMask]
        }
    }

    @usableFromInline
    internal var storage: Storage

    @usableFromInline
    static let pageShift = 12

    @usableFromInline
    static let pageSize = 1 << pageShift

    @usableFromInline
    static let pageMask = pageSize - 1

    @usableFromInline
    internal static var emptyPage: ContiguousArray<Value> {
        ContiguousArray(repeating: Value(index: Value.notFound), count: pageSize)
    }

    @inlinable @inline(__always)
    public init() {
        storage = Storage()
    }

    @inlinable @inline(__always)
    public init(arrayLiteral elements: Value...) {
        self.init()
        append(contentsOf: elements)
    }

    @inlinable @inline(__always)
    mutating func ensureUniqueStorage() {
        if !isKnownUniquelyReferenced(&storage) {
            storage = storage.copy()
        }
    }

    @inlinable @inline(__always)
    static func pageIndex(for rawIndex: Int) -> Int {
        rawIndex >> pageShift
    }

    @inlinable @inline(__always)
    static func offset(for rawIndex: Int) -> Int {
        rawIndex & pageMask
    }

    @inlinable @inline(__always)
    func readValue(at rawIndex: Int) -> Value {
        storage.value(at: rawIndex)
    }

    @inlinable @inline(__always)
    mutating func ensurePage(for rawIndex: Int) {
        ensureUniqueStorage()
        let pageIndex = Self.pageIndex(for: rawIndex)
        if pageIndex >= storage.pages.count {
            let missing = pageIndex + 1 - storage.pages.count
            storage.pages.append(contentsOf: repeatElement(nil, count: missing))
        }
        if storage.pages[pageIndex] == nil {
            storage.pages[pageIndex] = Self.emptyPage
        }
    }

    @inlinable @inline(__always)
    mutating func ensureCapacity(for rawIndex: Int) {
        ensurePage(for: rawIndex)
        if rawIndex + 1 > storage.logicalCount {
            storage.logicalCount = rawIndex + 1
        }
    }

    @inlinable @inline(__always)
    public mutating func ensureCapacity(for index: Index) {
        ensureCapacity(for: index.index)
    }

    @inlinable @inline(__always)
    public var startIndex: Index {
        Index(index: 0)
    }

    @inlinable @inline(__always)
    public var endIndex: Index {
        Index(index: storage.logicalCount)
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
        storage.logicalCount
    }

    @inlinable @inline(__always)
    public subscript(index: Index) -> Value {
        _read {
            yield readValue(at: index.index)
        }
        _modify {
            ensureCapacity(for: index.index)
            let pageIndex = Self.pageIndex(for: index.index)
            let elementIndex = Self.offset(for: index.index)
            yield &storage.pages[pageIndex]![elementIndex]
        }
    }

    @inlinable @inline(__always)
    public func contains(index: Index) -> Bool {
        index.index < storage.logicalCount
    }

    @inlinable @inline(__always)
    public mutating func append<S>(contentsOf newElements: S) where Element == S.Element, S: Sequence {
        var current = storage.logicalCount
        for element in newElements {
            self[Index(index: current)] = element
            current += 1
        }
    }

    @inlinable @inline(__always)
    public mutating func reserveCapacity(minimumCapacity: Int) {
        ensureUniqueStorage()
        let requiredPages = (minimumCapacity + Self.pageSize - 1) >> Self.pageShift
        if requiredPages > storage.pages.count {
            let missing = requiredPages - storage.pages.count
            storage.pages.append(contentsOf: repeatElement(nil, count: missing))
        }
    }

    public struct Values: RandomAccessCollection {
        public typealias Element = Value
        public typealias Index = Int

        @usableFromInline
        let storage: Storage

        @usableFromInline
        init(storage: Storage) {
            self.storage = storage
        }

        @inlinable @inline(__always)
        public var startIndex: Int { 0 }

        @inlinable @inline(__always)
        public var endIndex: Int { storage.logicalCount }

        @inlinable @inline(__always)
        public var count: Int { storage.logicalCount }

        @inlinable @inline(__always)
        public func index(after i: Int) -> Int { i + 1 }

        @inlinable @inline(__always)
        public func index(before i: Int) -> Int { i - 1 }

        @inlinable @inline(__always)
        public subscript(position: Int) -> Value {
            storage.value(at: position)
        }

        @inlinable @inline(__always)
        public var indices: Range<Int> { 0..<storage.logicalCount }
    }

    @usableFromInline
    public var values: Values {
        Values(storage: storage)
    }
}
