public struct SparseSet<Component, SlotIndex: SparseSetIndex>: Collection, RandomAccessCollection {
    @usableFromInline
    var components: PagedArray<Component> = []

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
let pageShift = 12

@usableFromInline
let pageSize = 1 << pageShift

@usableFromInline
let pageMask = pageSize - 1

@usableFromInline
final class _PagedArrayBuffer<Element>: ManagedBuffer<Void, Element> {
    @usableFromInline
    var initializedCount: Int = 0

    @usableFromInline
    static func create(minimumCapacity: Int) -> _PagedArrayBuffer<Element> {
        let storage = super.create(minimumCapacity: minimumCapacity) { _ in () }
        return unsafeDowncast(storage, to: _PagedArrayBuffer<Element>.self)
    }

    @usableFromInline
    func withMutableElements<R>(_ body: (UnsafeMutablePointer<Element>) throws -> R) rethrows -> R {
        try self.withUnsafeMutablePointerToElements { pointer in
            try body(pointer)
        }
    }

    deinit {
        if initializedCount > 0 {
            _ = self.withUnsafeMutablePointerToElements { pointer in
                pointer.deinitialize(count: initializedCount)
            }
        }
    }
}

public struct PagedArray<Element>: RandomAccessCollection, MutableCollection, ExpressibleByArrayLiteral {
    public typealias Index = Int

    @usableFromInline
    struct Storage {
        @usableFromInline
        var buffer: _PagedArrayBuffer<Element>? = nil

        @usableFromInline
        var count: Int = 0

        @usableFromInline
        var capacity: Int = 0

        @usableFromInline
        var isUnique: Bool {
            mutating get {
                guard buffer != nil else { return true }
                return isKnownUniquelyReferenced(&buffer)
            }
        }

        @usableFromInline
        mutating func updateInitializedCount() {
            buffer?.initializedCount = count
        }
    }

    @usableFromInline
    var storage = Storage()

    @inlinable @inline(__always)
    public init() {}

    @inlinable @inline(__always)
    public init(arrayLiteral elements: Element...) {
        self.init()
        append(contentsOf: elements)
    }

    @inlinable @inline(__always)
    public init<S: Sequence>(_ elements: S) where S.Element == Element {
        self.init()
        let estimated = elements.underestimatedCount
        if estimated > 0 {
            reserveCapacity(minimumCapacity: estimated)
        }
        for element in elements {
            append(element)
        }
    }

    @inlinable @inline(__always)
    public var startIndex: Int { 0 }

    @inlinable @inline(__always)
    public var endIndex: Int { storage.count }

    @inlinable @inline(__always)
    public var count: Int { storage.count }

    @inlinable @inline(__always)
    public var indices: Range<Int> { 0..<storage.count }

    @inlinable @inline(__always)
    public mutating func reserveCapacity(minimumCapacity: Int) {
        ensureUniqueStorage(minimumCapacity: minimumCapacity)
        storage.updateInitializedCount()
    }

    @inlinable @inline(__always)
    public mutating func append(_ newElement: Element) {
        ensureUniqueStorage(minimumCapacity: storage.count + 1)
        let pointer = basePointer()
        pointer.advanced(by: storage.count).initialize(to: newElement)
        storage.count += 1
        storage.updateInitializedCount()
    }

    @inlinable @inline(__always)
    public mutating func append<S: Sequence>(contentsOf newElements: S) where S.Element == Element {
        for element in newElements {
            append(element)
        }
    }

    @inlinable @inline(__always)
    @discardableResult
    public mutating func popLast() -> Element? {
        guard !isEmpty else { return nil }
        return removeLast()
    }

    @inlinable @inline(__always)
    @discardableResult
    public mutating func removeLast() -> Element {
        precondition(!isEmpty, "Cannot removeLast from empty PagedArray")
        ensureUniqueStorage(minimumCapacity: storage.count)
        let newCount = storage.count - 1
        let pointer = basePointer().advanced(by: newCount)
        let value = pointer.move()
        storage.count = newCount
        storage.updateInitializedCount()
        return value
    }

    @inlinable @inline(__always)
    public mutating func swapAt(_ i: Int, _ j: Int) {
        if i == j { return }
        precondition(i >= 0 && i < storage.count)
        precondition(j >= 0 && j < storage.count)
        ensureUniqueStorage(minimumCapacity: storage.count)
        let pointer = basePointer()
        swap(&pointer[i], &pointer[j])
    }

    @inlinable @inline(__always)
    public func index(after i: Int) -> Int { i + 1 }

    @inlinable @inline(__always)
    public func index(before i: Int) -> Int { i - 1 }

    @inlinable @inline(__always)
    public subscript(position: Int) -> Element {
        _read {
            precondition(position >= 0 && position < storage.count)
            let pointer = basePointer()
            yield pointer[position]
        }
        _modify {
            precondition(position >= 0 && position < storage.count)
            ensureUniqueStorage(minimumCapacity: storage.count)
            var pointer = basePointer()
            yield &pointer[position]
            storage.updateInitializedCount()
        }
    }

    @available(*, unavailable, message: "PagedArray storage does not expose contiguous mutable buffers.")
    @inlinable @inline(__always)
    mutating func withUnsafeMutableBufferPointer<R>(
        _ body: (inout UnsafeMutableBufferPointer<Element>) throws -> R
    ) rethrows -> R {
        fatalError("PagedArray.withUnsafeMutableBufferPointer is unavailable for paged storage.")
    }

    @usableFromInline @inline(__always)
    mutating func ensureUniqueStorage(minimumCapacity: Int) {
        let neededCapacity = Swift.max(minimumCapacity, storage.count)
        if neededCapacity == 0 {
            if storage.buffer == nil { return }
            if !storage.isUnique {
                reallocateBuffer(newCapacity: storage.capacity)
            }
            return
        }
        if storage.buffer == nil {
            let capacity = Swift.max(alignedCapacity(for: neededCapacity), pageSize)
            allocateBuffer(capacity: capacity, copyExistingCount: 0)
            return
        }

        if storage.capacity < neededCapacity {
            let capacity = alignedCapacity(for: neededCapacity)
            reallocateBuffer(newCapacity: capacity)
            return
        }

        if !storage.isUnique {
            reallocateBuffer(newCapacity: storage.capacity)
        }
    }

    @usableFromInline @inline(__always)
    mutating func reallocateBuffer(newCapacity: Int) {
        let copyCount = storage.count
        let oldBuffer = storage.buffer
        allocateBuffer(capacity: newCapacity, copyExistingCount: copyCount)
        oldBuffer?.initializedCount = copyCount
    }

    @usableFromInline @inline(__always)
    mutating func allocateBuffer(capacity: Int, copyExistingCount count: Int) {
        let buffer = _PagedArrayBuffer<Element>.create(minimumCapacity: capacity)
        if let oldBuffer = storage.buffer, count > 0 {
            buffer.withMutableElements { destination in
                oldBuffer.withMutableElements { source in
                    destination.initialize(from: source, count: count)
                }
            }
        }
        storage.buffer = buffer
        storage.capacity = capacity
        buffer.initializedCount = count
    }

    @usableFromInline @inline(__always)
    func alignedCapacity(for minimum: Int) -> Int {
        guard minimum > 0 else { return pageSize }
        var capacity = storage.capacity > 0 ? storage.capacity : pageSize
        while capacity < minimum {
            let doubled = capacity << 1
            if doubled < capacity { // overflow
                capacity = minimum
                break
            }
            capacity = Swift.max(doubled, capacity + pageSize)
            if capacity < 0 { // overflow to negative
                capacity = minimum
                break
            }
        }
        let remainder = capacity & pageMask
        if remainder == 0 { return capacity }
        let adjustment = pageSize - remainder
        if capacity > Int.max - adjustment {
            return Int.max
        }
        return capacity + adjustment
    }

    @usableFromInline @inline(__always)
    func basePointer() -> UnsafeMutablePointer<Element> {
        guard let buffer = storage.buffer else {
            fatalError("PagedArray has no allocated storage")
        }
        return buffer.withMutableElements { $0 }
    }

    @usableFromInline @inline(__always)
    func pointer(at index: Int) -> UnsafeMutablePointer<Element> {
        precondition(index >= 0 && index < storage.count)
        return basePointer().advanced(by: index)
    }

    @usableFromInline @inline(__always)
    mutating func mutablePointer(at index: Int) -> UnsafeMutablePointer<Element> {
        precondition(index >= 0 && index < storage.count)
        ensureUniqueStorage(minimumCapacity: storage.count)
        return basePointer().advanced(by: index)
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
        values.reserveCapacity(minimumCapacity: minimumCapacity)
    }
}
