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

@usableFromInline
final class SparseArrayPage<Value: SparseArrayValue> {
    @usableFromInline
    let buffer: PageBuffer<Value>

    @usableFromInline
    let elements: UnsafeMutablePointer<Value>

    @usableFromInline
    init() {
        buffer = PageBuffer<Value>.createPage()
        elements = buffer.withUnsafeMutablePointerToElements { pointer in
            pointer.initialize(repeating: Value(index: Value.notFound), count: pageCapacity)
            return pointer
        }
    }

    deinit {
        elements.deinitialize(count: pageCapacity)
    }

    @usableFromInline @inline(__always)
    func value(at offset: Int) -> Value {
        elements.advanced(by: offset).pointee
    }

    @usableFromInline @inline(__always)
    func update(_ value: Value, at offset: Int) -> Value {
        let pointer = elements.advanced(by: offset)
        let previous = pointer.pointee
        pointer.pointee = value
        return previous
    }
    @usableFromInline @inline(__always)
    func assign(from other: SparseArrayPage<Value>) {
        elements.assign(from: other.elements, count: pageCapacity)
    }
}

@usableFromInline
final class SparseArrayStorage<Value: SparseArrayValue> {
    @usableFromInline
    var pages: ContiguousArray<SparseArrayPage<Value>?>

    @usableFromInline
    var occupancies: ContiguousArray<Int>

    @usableFromInline
    init() {
        pages = []
        occupancies = []
    }

    @usableFromInline
    init(copying other: SparseArrayStorage<Value>) {
        occupancies = other.occupancies
        pages = ContiguousArray(other.pages.map { page -> SparseArrayPage<Value>? in
            guard let page else { return nil }
            let copy = SparseArrayPage<Value>()
            copy.assign(from: page)
            return copy
        })
    }

    @usableFromInline @inline(__always)
    func ensurePage(at pageIndex: Int) -> SparseArrayPage<Value> {
        if pageIndex >= pages.count {
            let missing = pageIndex + 1 - pages.count
            pages.append(contentsOf: repeatElement(nil, count: missing))
            occupancies.append(contentsOf: repeatElement(0, count: missing))
        }

        if let existing = pages[pageIndex] {
            return existing
        }

        let page = SparseArrayPage<Value>()
        pages[pageIndex] = page
        return page
    }

    @usableFromInline @inline(__always)
    func value(at index: Int) -> Value {
        let pageIndex = index >> pageShift
        guard pageIndex < pages.count, let page = pages[pageIndex] else {
            return Value(index: Value.notFound)
        }
        let offset = index & pageMask
        return page.value(at: offset)
    }

    @usableFromInline @inline(__always)
    func contains(index: Int) -> Bool {
        let pageIndex = index >> pageShift
        guard pageIndex < pages.count else { return false }
        return pages[pageIndex] != nil
    }

    @usableFromInline @inline(__always)
    func set(_ value: Value, at index: Int) {
        let pageIndex = index >> pageShift
        let offset = index & pageMask

        if value.index == Value.notFound {
            guard pageIndex < pages.count, let page = pages[pageIndex] else {
                return
            }
            let previous = page.update(value, at: offset)
            if previous.index != Value.notFound {
                occupancies[pageIndex] &-= 1
                if occupancies[pageIndex] == 0 {
                    pages[pageIndex] = nil
                    trimTrailingEmptyPages()
                }
            }
            return
        }

        let page = ensurePage(at: pageIndex)
        let previous = page.update(value, at: offset)
        if previous.index == Value.notFound {
            occupancies[pageIndex] &+= 1
        }
    }

    @usableFromInline
    func trimTrailingEmptyPages() {
        while let last = pages.last, last == nil {
            pages.removeLast()
            occupancies.removeLast()
        }
    }

    @usableFromInline @inline(__always)
    var capacity: Int {
        pages.count * pageCapacity
    }
}

public struct SparseArrayView<Value: SparseArrayValue> {
    @usableFromInline
    let storage: Unmanaged<SparseArrayStorage<Value>>

    @usableFromInline
    init(_ storage: SparseArrayStorage<Value>) {
        self.storage = .passUnretained(storage)
    }

    @inlinable @inline(__always)
    public var count: Int {
        storage._withUnsafeGuaranteedRef { $0.capacity }
    }

    @inlinable @inline(__always)
    public subscript(index: Int) -> Value {
        storage._withUnsafeGuaranteedRef { $0.value(at: index) }
    }

    @inlinable @inline(__always)
    public func contains(index: Int) -> Bool {
        storage._withUnsafeGuaranteedRef { $0.contains(index: index) }
    }
}

public struct SparseArray<Value: SparseArrayValue, Index: SparseSetIndex>: Collection, ExpressibleByArrayLiteral, RandomAccessCollection {
    @usableFromInline
    var storage: SparseArrayStorage<Value> = SparseArrayStorage()

    @usableFromInline
    mutating func ensureUniqueStorage() {
        if !isKnownUniquelyReferenced(&storage) {
            storage = SparseArrayStorage(copying: storage)
        }
    }

    @inlinable @inline(__always)
    public init() {}

    @inlinable @inline(__always)
    public init(arrayLiteral elements: Value...) {
        self.init()
        for (index, element) in elements.enumerated() {
            self[Index(index: index)] = element
        }
    }

    @inlinable @inline(__always)
    public var startIndex: Index {
        Index(index: 0)
    }

    @inlinable @inline(__always)
    public var endIndex: Index {
        Index(index: storage.capacity)
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
        storage.capacity
    }

    @inlinable @inline(__always)
    public subscript(index: Index) -> Value {
        get { storage.value(at: index.index) }
        set {
            ensureUniqueStorage()
            storage.set(newValue, at: index.index)
        }
    }

    @inlinable @inline(__always)
    public func contains(index: Index) -> Bool {
        storage.contains(index: index.index)
    }

    @inlinable @inline(__always)
    public mutating func reserveCapacity(minimumCapacity: Int) {
        // Reserving capacity is a no-op for the sparse array. Pages are allocated on demand.
    }

    @inlinable @inline(__always)
    public var view: SparseArrayView<Value> {
        SparseArrayView(storage)
    }
}
