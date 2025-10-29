@usableFromInline
struct PageCursor<Element> {
    @usableFromInline var lastPageIndex: Int = -1
    @usableFromInline var elements: UnsafeMutablePointer<Element>? = nil

    @usableFromInline
    init(lastPageIndex: Int = -1, elements: UnsafeMutablePointer<Element>? = nil) {
        self.lastPageIndex = lastPageIndex
        self.elements = elements
    }
}

extension UnmanagedPagedStorage {
    @inlinable @inline(__always)
    func load(at index: Int, using cursor: inout PageCursor<Component>) -> Component {
        let pageIndex = index >> pageShift
        let offset = index & pageMask
        if cursor.lastPageIndex != pageIndex {
            if pageIndex < pageCount {
                cursor.elements = pages.advanced(by: pageIndex).pointee.baseAddress
            } else {
                cursor.elements = nil
            }
            cursor.lastPageIndex = pageIndex
        }
        guard let elements = cursor.elements else {
            return missingPageValue()
        }
        return elements.advanced(by: offset).pointee
    }

    @inlinable @inline(__always)
    func isNotFound(at index: Int, using cursor: inout PageCursor<ContiguousArray.Index>) -> Bool where Component == ContiguousArray.Index {
        load(at: index, using: &cursor) == .notFound
    }

    @inlinable
    func missingPageValue() -> Component {
        if Component.self == ContiguousArray<Void>.Index.self {
            return unsafeBitCast(ContiguousArray<Void>.Index.notFound, to: Component.self)
        }
        fatalError("Attempted to access a missing page in UnmanagedPagedStorage for type \(Component.self)")
    }
}

extension UnsafePagedStorage {
    @inlinable @inline(__always)
    func load(at index: Int, using cursor: inout PageCursor<Element>) -> Element {
        guard index < count else { return missingPageValue() }
        let pageIndex = index >> pageShift
        let offset = index & pageMask
        if cursor.lastPageIndex != pageIndex {
            if pageIndex < pageCount {
                cursor.elements = baseAddress.advanced(by: pageIndex).pointee.baseAddress
            } else {
                cursor.elements = nil
            }
            cursor.lastPageIndex = pageIndex
        }
        guard let elements = cursor.elements else {
            return missingPageValue()
        }
        return elements.advanced(by: offset).pointee
    }

    @inlinable @inline(__always)
    func isNotFound(at index: Int, using cursor: inout PageCursor<ContiguousArray.Index>) -> Bool where Element == ContiguousArray.Index {
        load(at: index, using: &cursor) == .notFound
    }

    @inlinable
    func missingPageValue() -> Element {
        if Element.self == ContiguousArray<Void>.Index.self {
            return unsafeBitCast(ContiguousArray<Void>.Index.notFound, to: Element.self)
        }
        fatalError("Attempted to access a missing page in UnsafePagedStorage for type \(Element.self)")
    }
}

public struct UnsafePagedStorage<Element> {
    @usableFromInline
    let baseAddress: UnsafeMutablePointer<UnsafeMutableBufferPointer<Element>>
    @usableFromInline
    let count: Int
    @usableFromInline
    let pageCount: Int

    @inlinable @inline(__always)
    public init(baseAddress: UnsafeMutablePointer<UnsafeMutableBufferPointer<Element>>, count: Int, pageCount: Int) {
        self.baseAddress = baseAddress
        self.count = count
        self.pageCount = pageCount
    }

    @inlinable @inline(__always)
    public init(_ storage: PagedStorage<Element>) {
        let pointer = storage.pages.baseAddress!
        self = UnsafePagedStorage(baseAddress: pointer, count: storage.count, pageCount: storage.pageCount)
    }

    @inlinable @inline(__always)
    public subscript(index: Int) -> Element {
        _read {
            guard index < count else {
                yield missingPageValue()
                return
            }
            let pageIndex = index >> pageShift
            let offset = index & pageMask
            guard pageIndex < pageCount else {
                yield missingPageValue()
                return
            }
            let page = baseAddress.advanced(by: pageIndex).pointee
            guard let base = page.baseAddress else {
                yield missingPageValue()
                return
            }
            yield base.advanced(by: offset).pointee
        }
    }
}

@usableFromInline
let defaultInitialPageCapacity = 1

@usableFromInline
let defaultInitialCapacity = 1

public let pageShift = 10 // 10 -> 1024, 20 -> 1M

public let pageCapacity = 1 << pageShift

public let pageMask = pageCapacity - 1


public struct UnmanagedPagedStorage<Component> {
    public var count: Int

    public var pageCount: Int

    @usableFromInline
    public var pages: UnsafeMutablePointer<UnsafeMutableBufferPointer<Component>>

    @inlinable @inline(__always)
    public init(_ storage: PagedStorage<Component>) {
        self.count = storage.count
        self.pageCount = storage.pageCount
        self.pages = storage.pages.baseAddress!
    }

    @inlinable @inline(__always)
    public init(pages: UnsafeMutablePointer<UnsafeMutableBufferPointer<Component>>, count: Int, pageCount: Int) {
        self.count = count
        self.pageCount = pageCount
        self.pages = pages
    }

    @inlinable @inline(__always)
    public subscript(index: Int) -> Component {
        @_transparent
        unsafeAddress {
            UnsafePointer(elementPointer(index))
        }

        @_transparent
        unsafeMutableAddress {
            elementPointer(index)
        }
    }

    @inlinable @inline(__always)
    public func elementPointer(_ index: Int) -> UnsafeMutablePointer<Component> {
        precondition(index < count)
        let pageIndex = index >> pageShift
        let offset = index & pageMask
        precondition(pageIndex < pageCount)
        let page = pages.advanced(by: pageIndex).pointee
        guard let base = page.baseAddress else {
            fatalError("Missing page while requesting pointer")
        }
        return base.advanced(by: offset)
    }
}

public struct PagedStorage<Element> {
    public var count: Int

    public var pageCount: Int

    @usableFromInline
    public var pages: UnsafeMutableBufferPointer<UnsafeMutableBufferPointer<Element>>

    @inlinable @inline(__always)
    public init(initialPageCapacity: Int = defaultInitialPageCapacity) {
        precondition(initialPageCapacity > 0)
        self.count = 0
        self.pageCount = 0
        var buffer = UnsafeMutableBufferPointer<UnsafeMutableBufferPointer<Element>>.allocate(capacity: initialPageCapacity)
        for index in 0..<initialPageCapacity {
            buffer.baseAddress!.advanced(by: index).initialize(to: UnsafeMutableBufferPointer<Element>())
        }
        self.pages = buffer
    }

    @inlinable @inline(__always)
    mutating func reset(initialPageCapacity: Int = defaultInitialPageCapacity) {
        deallocateAllPages()
        precondition(initialPageCapacity > 0)
        var buffer = UnsafeMutableBufferPointer<UnsafeMutableBufferPointer<Element>>.allocate(capacity: initialPageCapacity)
        for index in 0..<initialPageCapacity {
            buffer.baseAddress!.advanced(by: index).initialize(to: UnsafeMutableBufferPointer<Element>())
        }
        pages = buffer
        count = 0
        pageCount = 0
    }

    @inlinable @inline(__always)
    public var capacity: Int {
        pages.count
    }

    @inlinable @inline(__always)
    public var unsafeAddress: UnsafeMutablePointer<UnsafeMutableBufferPointer<Element>> {
        pages.baseAddress!
    }

    @inlinable @inline(__always)
    mutating func ensureSlot(forPage pageIndex: Int) {
        if pageIndex >= pageCount {
            let required = pageIndex + 1
            ensureCapacity(forPageCount: required)
            for i in pageCount..<required {
                pages.baseAddress!.advanced(by: i).pointee = UnsafeMutableBufferPointer<Element>()
            }
            pageCount = required
        }
        updateCountForPageIndex(pageIndex)
    }

    @inlinable @inline(__always)
    mutating func ensurePage(forPage pageIndex: Int) -> UnsafeMutableBufferPointer<Element> {
        ensureSlot(forPage: pageIndex)
        var page = pages.baseAddress!.advanced(by: pageIndex).pointee
        if page.baseAddress == nil {
            page = allocatePage()
            pages.baseAddress!.advanced(by: pageIndex).pointee = page
        }
        return page
    }

    @inlinable @inline(__always)
    func page(at pageIndex: Int) -> UnsafeMutableBufferPointer<Element>? {
        guard pageIndex < pageCount else { return nil }
        let page = pages.baseAddress!.advanced(by: pageIndex).pointee
        guard page.baseAddress != nil else { return nil }
        return page
    }

    @inlinable @inline(__always)
    mutating func removePage(at pageIndex: Int) {
        guard pageIndex < pageCount else { return }
        let pointer = pages.baseAddress!.advanced(by: pageIndex)
        deallocatePage(pointer.pointee)
        pointer.pointee = UnsafeMutableBufferPointer<Element>()
        shrinkTrailingNilPages()
    }

    @inlinable @inline(__always)
    mutating func shrinkTrailingNilPages() {
        while pageCount > 0 {
            let lastIndex = pageCount - 1
            let page = pages.baseAddress!.advanced(by: lastIndex).pointee
            if page.baseAddress == nil {
                pageCount = lastIndex
            } else {
                break
            }
        }
        if pageCount == 0 {
            count = 0
        } else {
            let upperBound = pageCount << pageShift
            if count > upperBound {
                count = upperBound
            }
        }
    }

    @inlinable @inline(__always)
    mutating func updateCountForPageIndex(_ pageIndex: Int) {
        let upperBound = (pageIndex + 1) << pageShift
        if count < upperBound {
            count = upperBound
        }
    }

    @inlinable @inline(__always)
    public subscript(_ index: Int) -> Element {
        @inlinable
        _read {
            yield readElement(at: index)
        }
        @inlinable
        _modify {
            let pointer = elementPointer(at: index)
            yield &pointer.pointee
        }
    }

    @inlinable @inline(__always)
    public mutating func append(_ component: Element) {
        let nextIndex = count
        let pageIndex = nextIndex >> pageShift
        let offset = nextIndex & pageMask
        var page = ensurePage(forPage: pageIndex)
        guard let base = page.baseAddress else {
            fatalError("Missing page while appending element")
        }
        base.advanced(by: offset).initialize(to: component)
        pages.baseAddress!.advanced(by: pageIndex).pointee = page
        count = nextIndex + 1
    }

    @inlinable @inline(__always)
    @discardableResult
    public mutating func remove(at index: Int) -> Element {
        precondition(index < count)
        let lastIndex = count - 1
        let lastPageIndex = lastIndex >> pageShift
        let lastOffset = lastIndex & pageMask
        let pageIndex = index >> pageShift
        let offset = index & pageMask

        let pagePointer = pages.baseAddress!.advanced(by: pageIndex)
        guard let pageBase = pagePointer.pointee.baseAddress else {
            fatalError("Missing page while removing element")
        }
        let removed = pageBase.advanced(by: offset).move()

        if index != lastIndex {
            let lastPagePointer = pages.baseAddress!.advanced(by: lastPageIndex)
            guard let lastBase = lastPagePointer.pointee.baseAddress else {
                fatalError("Missing last page while removing element")
            }
            pageBase.advanced(by: offset).moveInitialize(from: lastBase.advanced(by: lastOffset), count: 1)
        }

        count = lastIndex

        if lastOffset == 0 {
            let lastPagePointer = pages.baseAddress!.advanced(by: lastPageIndex)
            deallocatePage(lastPagePointer.pointee)
            lastPagePointer.pointee = UnsafeMutableBufferPointer<Element>()
            shrinkTrailingNilPages()
        }

        return removed
    }

    @inlinable @inline(__always) @discardableResult
    public mutating func removeLast() -> Element {
        precondition(count > 0)
        let lastIndex = count - 1
        let pageIndex = lastIndex >> pageShift
        let offset = lastIndex & pageMask
        var page = pages.baseAddress!.advanced(by: pageIndex).pointee
        guard let base = page.baseAddress else {
            fatalError("Missing page while removing last element")
        }
        let removed = base.advanced(by: offset).move()
        if offset == 0 {
            deallocatePage(page)
            pages.baseAddress!.advanced(by: pageIndex).pointee = UnsafeMutableBufferPointer<Element>()
            pageCount = pageIndex
            shrinkTrailingNilPages()
        }
        count = lastIndex
        return removed
    }

    @inlinable @inline(__always)
    public mutating func swapAt(_ i: Int, _ j: Int) {
        precondition(i != j)
        let pageIndexI = i >> pageShift
        let offsetI = i & pageMask
        let pageIndexJ = j >> pageShift
        let offsetJ = j & pageMask

        let pointerI = pages.baseAddress!.advanced(by: pageIndexI)
        let pointerJ = pages.baseAddress!.advanced(by: pageIndexJ)
        guard let baseI = pointerI.pointee.baseAddress else { fatalError("Missing page during swap") }
        guard let baseJ = pointerJ.pointee.baseAddress else { fatalError("Missing page during swap") }

        let iValue = baseI.advanced(by: offsetI).move()
        baseI.advanced(by: offsetI).moveInitialize(from: baseJ.advanced(by: offsetJ), count: 1)
        baseJ.advanced(by: offsetJ).initialize(to: iValue)
    }

    @inlinable @inline(__always)
    mutating func ensureCapacity(forPageCount requiredPageCount: Int) {
        if requiredPageCount <= capacity {
            return
        }

        let newCapacity = Swift.max(capacity << 1, requiredPageCount)
        let oldBuffer = pages
        let oldCapacity = oldBuffer.count
        var newBuffer = UnsafeMutableBufferPointer<UnsafeMutableBufferPointer<Element>>.allocate(capacity: newCapacity)
        let newBase = newBuffer.baseAddress!
        let oldBase = oldBuffer.baseAddress!
        for index in 0..<oldCapacity {
            newBase.advanced(by: index).initialize(to: oldBase.advanced(by: index).move())
        }
        if newCapacity > oldCapacity {
            for index in oldCapacity..<newCapacity {
                newBase.advanced(by: index).initialize(to: UnsafeMutableBufferPointer<Element>())
            }
        }
        pages = newBuffer
        oldBuffer.deallocate()
    }

    @inlinable @inline(__always)
    func readElement(at index: Int) -> Element {
        precondition(index < count)
        let pageIndex = index >> pageShift
        let offset = index & pageMask
        let page = pages.baseAddress!.advanced(by: pageIndex).pointee
        guard let base = page.baseAddress else {
            fatalError("Missing page while reading element")
        }
        return base.advanced(by: offset).pointee
    }

    @inlinable @inline(__always)
    func elementPointer(at index: Int) -> UnsafeMutablePointer<Element> {
        precondition(index < count)
        let pageIndex = index >> pageShift
        let offset = index & pageMask
        let page = pages.baseAddress!.advanced(by: pageIndex).pointee
        guard let base = page.baseAddress else {
            fatalError("Missing page while requesting pointer")
        }
        return base.advanced(by: offset)
    }

    @inlinable @inline(__always)
    func allocatePage() -> UnsafeMutableBufferPointer<Element> {
        let pointer = UnsafeMutablePointer<Element>.allocate(capacity: pageCapacity)
        return UnsafeMutableBufferPointer(start: pointer, count: pageCapacity)
    }

    @inlinable @inline(__always)
    func deallocatePage(_ page: UnsafeMutableBufferPointer<Element>) {
        guard let base = page.baseAddress else { return }
        base.deinitialize(count: page.count)
        base.deallocate()
    }

    @inlinable @inline(__always)
    mutating func deallocateAllPages() {
        guard let base = pages.baseAddress else { return }
        for index in 0..<pages.count {
            deallocatePage(base.advanced(by: index).pointee)
        }
        base.deinitialize(count: pages.count)
        pages.deallocate()
        pages = UnsafeMutableBufferPointer()
        count = 0
        pageCount = 0
    }
}
