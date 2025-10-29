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
            cursor.elements = pages._withUnsafeGuaranteedRef { buf in
                buf.withElements(atPage: pageIndex) { pagePtr in
                    pagePtr.pointee.withUnsafeMutablePointerToElements { $0 }
                }
            }
            cursor.lastPageIndex = pageIndex
        }
        return cursor.elements!.advanced(by: offset).pointee
    }

    @inlinable @inline(__always)
    func isNotFound(at index: Int, using cursor: inout PageCursor<ContiguousArray.Index>) -> Bool where Component == ContiguousArray.Index {
        load(at: index, using: &cursor) == .notFound
    }
}

extension UnsafePagedStorage {
    @inlinable @inline(__always)
    func load(at index: Int, using cursor: inout PageCursor<Element>) -> Element {
        guard index < count else { return missingPageValue() }
        let pageIndex = index >> pageShift
        let offset = index & pageMask
        if cursor.lastPageIndex != pageIndex {
            if pageIndex < pageCount, let pageBase = baseAddress[pageIndex] {
                cursor.elements = pageBase
                    .advanced(by: MemoryLayout<Int64>.stride * 2)
                    .assumingMemoryBound(to: Element.self)
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
        if Element.self == ContiguousArray.Index.self {
            return unsafeBitCast(ContiguousArray.Index.notFound, to: Element.self)
        }
        fatalError("Attempted to access a missing page in UnsafePagedStorage for type \(Element.self)")
    }
}

public struct UnsafePagedStorage<Element> {
    @usableFromInline
    let baseAddress: UnsafeMutablePointer<UnsafeMutableRawPointer?>
    @usableFromInline
    let count: Int
    @usableFromInline
    let pageCount: Int

    @inlinable @inline(__always)
    public init(baseAddress: UnsafeMutablePointer<UnsafeMutableRawPointer?>, count: Int, pageCount: Int) {
        self.baseAddress = baseAddress
        self.count = count
        self.pageCount = pageCount
    }

    @inlinable @inline(__always)
    public init(_ storage: PagedStorage<Element>) {
        let pointer = storage.unsafeAddress
        self = UnsafePagedStorage(baseAddress: pointer, count: storage.count, pageCount: storage.pageCount)
    }

    @inlinable @inline(__always)
    public subscript(index: Int) -> Element {
        _read {
            guard index < count else {
                yield missingPageValue()
                return
            }
            let page = index >> pageShift
            let offset = index & pageMask
            guard page < pageCount, let pageBase = baseAddress[page] else {
                yield missingPageValue()
                return
            }
            let elementPointer = UnsafePointer<Element>(
                pageBase
                    .advanced(by: MemoryLayout<Int64>.stride * 2)
                    .assumingMemoryBound(to: Element.self)
            )
            yield elementPointer.advanced(by: offset).pointee
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

    public var pages: Unmanaged<PagedBuffer<Component>>

    @inlinable @inline(__always)
    public init(_ storage: PagedStorage<Component>) {
        self.count = storage.count
        self.pageCount = storage.pageCount
        self.pages = .passUnretained(storage.pages)
    }

    @inlinable @inline(__always)
    public init(_ pages: Unmanaged<PagedBuffer<Component>>, count: Int, pageCount: Int) {
        self.count = count
        self.pageCount = pageCount
        self.pages = pages
    }

    @inlinable @inline(__always)
    public subscript(index: Int) -> Component {
        @_transparent
        unsafeAddress {
            UnsafePointer(pages._withUnsafeGuaranteedRef { $0.getUnsafePointer(index, pageCount: pageCount, count: count) })
        }

        @_transparent
        unsafeMutableAddress {
            pages._withUnsafeGuaranteedRef {
                $0.getUnsafePointer(index, pageCount: pageCount, count: count)
            }
        }
    }

    @inlinable @inline(__always)
    public func elementPointer(_ index: Int) -> UnsafeMutablePointer<Component> {
        pages._withUnsafeGuaranteedRef { x in
            x.getPointer(index, pageCount: pageCount, count: count)
        }
    }
}

public struct PagedStorage<Element> {
    public var count: Int

    public var pageCount: Int

    public var pages: PagedBuffer<Element>

    @inlinable @inline(__always)
    public init(initialPageCapacity: Int = defaultInitialPageCapacity) {
        precondition(initialPageCapacity > 0)
        self.count = 0
        self.pageCount = 0
        self.pages = PagedBuffer.create(initialCapacity: initialPageCapacity)
    }

    @inlinable @inline(__always)
    public var unsafeAddress: UnsafeMutablePointer<UnsafeMutableRawPointer?> {
        pages.withUnsafeMutablePointerToElements { pagesPointer in
            pagesPointer.withMemoryRebound(to: UnsafeMutableRawPointer?.self, capacity: pageCount) { pointer in
                pointer
            }
        }
    }

    @inlinable @inline(__always)
    mutating func ensureSlot(forPage pageIndex: Int) {
        if pageIndex >= pageCount {
            let required = pageIndex + 1
            let buffer = pages.ensureCapacity(forPageCount: required, storage: &self)
            buffer.initializeNil(from: pageCount, to: required)
            pages = buffer
            pageCount = required
        }
        updateCountForPageIndex(pageIndex)
    }

    @inlinable @inline(__always)
    mutating func ensurePage(forPage pageIndex: Int) -> PageBuffer<Element> {
        ensureSlot(forPage: pageIndex)
        let page = pages.ensurePageObject(at: pageIndex)
        return page
    }

    @inlinable @inline(__always)
    func page(at pageIndex: Int) -> PageBuffer<Element>? {
        guard pageIndex < pageCount else { return nil }
        return pages.page(at: pageIndex)
    }

    @inlinable @inline(__always)
    mutating func removePage(at pageIndex: Int) {
        guard pageIndex < pageCount else { return }
        pages.setPage(nil, at: pageIndex)
        shrinkTrailingNilPages()
    }

    @inlinable @inline(__always)
    mutating func shrinkTrailingNilPages() {
        while pageCount > 0 && pages.page(at: pageCount - 1) == nil {
            pages.deinitializeRange((pageCount - 1)..<pageCount)
            pageCount -= 1
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
            yield pages[index, pageCount, count]
        }
        @inlinable
        _modify {
            yield &pages[index, pageCount, count]
        }
    }

    @inlinable @inline(__always)
    public mutating func append(_ component: Element) {
        pages.append(component, storage: &self)
    }

    @inlinable @inline(__always) @discardableResult
    public mutating func removeLast() -> Element {
        precondition(count > 0)
        return pages.remove(at: count - 1, storage: &self)
    }

    @inlinable @inline(__always)
    public mutating func swapAt(_ i: Int, _ j: Int) {
        precondition(i != j)
        let pageIndexI = i >> pageShift
        let offsetI = i & pageMask
        let pageIndexJ = j >> pageShift
        let offsetJ = j & pageMask
        if pageIndexI == pageIndexJ {
            pages.withElements(atPage: pageIndexI) { pagePointer in
                pagePointer.pointee.withUnsafeMutablePointerToElements { elementsPointer in
                    let iValue = elementsPointer.advanced(by: offsetI).move()
                    elementsPointer.moveInitialize(from: elementsPointer.advanced(by: offsetJ), count: 1)
                    elementsPointer.advanced(by: offsetJ).initialize(to: iValue)
                }
            }
        } else {
            pages.withUnsafeMutablePointerToElements { pagesPointer in
                let pageIPointer = pagesPointer.advanced(by: pageIndexI)
                let pageJPointer = pagesPointer.advanced(by: pageIndexJ)
                pageIPointer.pointee.withUnsafeMutablePointerToElements { elementsIPointer in
                    pageJPointer.pointee.withUnsafeMutablePointerToElements { elementsJPointer in
                        let iValue = elementsIPointer.advanced(by: offsetI).move()
                        elementsIPointer.moveInitialize(from: elementsJPointer.advanced(by: offsetJ), count: 1)
                        elementsJPointer.advanced(by: offsetJ).initialize(to: iValue)
                    }
                }
            }
        }
    }
}

public final class PageBuffer<Element>: ManagedBuffer<Void, Element> {
    @inlinable @inline(__always)
    static func createPage() -> PageBuffer {
        unsafeDowncast(PageBuffer.create(minimumCapacity: pageCapacity) { _ in () }, to: PageBuffer.self)
    }

    @inlinable @inline(__always)
    func initializeElement(at index: Int, to value: Element) {
        precondition(index < pageCapacity)
        withUnsafeMutablePointerToElements { buffer in
            buffer.advanced(by: index).initialize(to: value)
        }
    }

    @inlinable @inline(__always)
    func moveInitializeElement(at index: Int, from other: PageBuffer, sourceIndex: Int) {
        precondition(index < pageCapacity)
        precondition(sourceIndex < pageCapacity)
        withUnsafeMutablePointerToElements { destination in
            other.withUnsafeMutablePointerToElements { source in
                destination.advanced(by: index).moveInitialize(from: source.advanced(by: sourceIndex), count: 1)
            }
        }
    }

    @inlinable @inline(__always)
    func moveElement(at index: Int) -> Element {
        precondition(index < pageCapacity)
        return withUnsafeMutablePointerToElements { buffer in
            buffer.advanced(by: index).move()
        }
    }

    @inlinable @inline(__always)
    func value(at index: Int) -> Element {
        precondition(index < pageCapacity)
        return withUnsafeMutablePointerToElements { buffer in
            buffer[index]
        }
    }

    @inlinable @inline(__always)
    subscript(index: Int) -> Element {
        @inlinable @inline(__always)
        _read {
            precondition(index < pageCapacity)
            yield withUnsafeMutablePointerToElements { buffer in
                buffer[index]
            }
        }
        @inlinable @inline(__always)
        _modify {
            let b = withUnsafeMutablePointerToElements { buffer in
                buffer
            }
            yield &b[index]
        }
    }
}

// TODO: Since I'm fighting so much with ARC and indirection. Just use an UnsafeBufferPointer instead of ManagedBuffer. See RigidArray.
public final class PagedBuffer<Element>: ManagedBuffer<Void, PageBuffer<Element>?> {
    @inlinable @inline(__always)
    public static func create(initialCapacity: Int = defaultInitialCapacity) -> PagedBuffer {
        precondition(initialCapacity > 0)
        let buffer = unsafeDowncast(PagedBuffer.create(minimumCapacity: initialCapacity) { _ in () }, to: PagedBuffer.self)
        buffer.initializeNil(from: 0, to: initialCapacity)
        return buffer
    }

    @inlinable @inline(__always)
    func initializeNil(from start: Int, to end: Int) {
        guard start < end else { return }
        withUnsafeMutablePointerToElements { pointer in
            pointer.advanced(by: start).initialize(repeating: nil, count: end - start)
        }
    }

    @inlinable @inline(__always)
    func deinitializeRange(_ range: Range<Int>) {
        guard !range.isEmpty else { return }
        withUnsafeMutablePointerToElements { pointer in
            pointer.advanced(by: range.lowerBound).deinitialize(count: range.count)
        }
    }

    @inlinable @inline(__always)
    func page(at index: Int) -> PageBuffer<Element>? {
        withUnsafeMutablePointerToElements { pointer in
            pointer.advanced(by: index).pointee
        }
    }

    @inlinable @inline(__always)
    func setPage(_ page: PageBuffer<Element>?, at index: Int) {
        withUnsafeMutablePointerToElements { pointer in
            pointer.advanced(by: index).pointee = page
        }
    }

    @inlinable @inline(__always) @discardableResult
    public func append(_ component: Element, storage: inout PagedStorage<Element>) -> Int {
        precondition(self === storage.pages)

        let nextIndex = storage.count
        let pageIndex = nextIndex >> pageShift
        let offset = nextIndex & pageMask

        _ = ensureCapacity(forPageCount: pageIndex + 1, storage: &storage)
        storage.ensureSlot(forPage: pageIndex)
        let page = storage.pages.ensurePageObject(at: pageIndex)
        page.initializeElement(at: offset, to: component)
        storage.count = nextIndex + 1
        return nextIndex
    }

    @inlinable @inline(__always)
    func ensurePageObject(at index: Int) -> PageBuffer<Element> {
        if let existing = page(at: index) {
            return existing
        }
        let newPage = PageBuffer<Element>.createPage()
        setPage(newPage, at: index)
        return newPage
    }

    @inlinable @inline(__always)
    func get(_ index: Int, pageCount: Int, count: Int) -> Element {
        precondition(index < count)
        let pageIndex = index >> pageShift
        let offset = index & pageMask
        precondition(pageIndex < pageCount)
        return withElements(atPage: pageIndex) { pagePointer in
            guard let page = pagePointer.pointee else {
                fatalError("Missing page while reading paged storage")
            }
            return page.withUnsafeMutablePointerToElements { elementsPointer in
                elementsPointer.advanced(by: offset).pointee
            }
        }
    }

    @inlinable @inline(__always)
    public func getPointer(_ index: Int, pageCount: Int, count: Int) -> UnsafeMutablePointer<Element> {
        precondition(index < count)
        let pageIndex = index >> pageShift
        let offset = index & pageMask
        precondition(pageIndex < pageCount)
        return withElements(atPage: pageIndex) { pagePointer in
            guard let page = pagePointer.pointee else {
                fatalError("Missing page while requesting pointer")
            }
            return page.withUnsafeMutablePointerToElements { elementsPointer in
                elementsPointer.advanced(by: offset)
            }
        }
    }

    @inlinable @inline(__always)
    public func getUnsafePointer(_ index: Int, pageCount: Int, count: Int) -> UnsafeMutablePointer<Element> {
        assert(index >= 0)
        assert(index < count)
        let pageIndex = index >> pageShift
        assert(pageIndex < pageCount)
        let offset = index & pageMask
        return withUnsafeMutablePointerToElements { pagesPointer in
            guard let page = pagesPointer[pageIndex] else {
                fatalError("Missing page while requesting unsafe pointer")
            }
            return page.withUnsafeMutablePointerToElements { elementsPointer in
                elementsPointer.advanced(by: offset)
            }
        }
    }

    @inlinable @inline(__always)
    public subscript(_ index: Int, pageCount: Int, count: Int) -> Element {
        @inlinable @inline(__always)
        unsafeAddress {
            UnsafePointer(getUnsafePointer(index, pageCount: pageCount, count: count))
        }

        @inlinable @inline(__always)
        unsafeMutableAddress {
            getUnsafePointer(index, pageCount: pageCount, count: count)
        }
    }

    @inlinable @inline(__always)
    @discardableResult
    func remove(at index: Int, storage: inout PagedStorage<Element>) -> Element {
        precondition(self === storage.pages)
        precondition(index < storage.count)

        let lastIndex = storage.count - 1
        let lastPageIndex = lastIndex >> pageShift
        let lastOffset = lastIndex & pageMask
        let pageIndex = index >> pageShift
        let offset = index & pageMask

        guard let page = withElements(atPage: pageIndex, body: \.pointee) else {
            fatalError("Removing element from non-existent page")
        }
        let removed = page.moveElement(at: offset)

        if index != lastIndex {
            guard let lastPage = withElements(atPage: lastPageIndex, body: \.pointee) else {
                fatalError("Missing last page during removal")
            }
            page.moveInitializeElement(at: offset, from: lastPage, sourceIndex: lastOffset)
        }

        storage.count = lastIndex

        if lastOffset == 0 {
            let lastPage = withElements(atPage: lastPageIndex, body: \.pointee)
            removeUninitialisedLastPage(storage: &storage, lastPageIndex: lastPageIndex, lastPage: lastPage)
        }

        return removed
    }

    @inlinable @inline(__always)
    func ensureCapacity(forPageCount requiredPageCount: Int, storage: inout PagedStorage<Element>) -> PagedBuffer {
        if requiredPageCount <= capacity {
            return self
        }

        let newCapacity = Swift.max(capacity << 1, requiredPageCount)
        let newBuffer = PagedBuffer.create(initialCapacity: newCapacity)
        let existingPageCount = storage.pageCount
        withUnsafeMutablePointerToElements { source in
            newBuffer.withUnsafeMutablePointerToElements { destination in
                destination.moveInitialize(from: source, count: existingPageCount)
            }
//                source.deallocate() // I think I don't need to deallocate anything. The page buffers are moved and stay at their retain count and the pages buffer will be handled by ManagedBuffer.
        }
        storage.pages = newBuffer
        return newBuffer
    }

    @inlinable @inline(__always)
    func initializePage(_ page: PageBuffer<Element>, at index: Int) {
        withUnsafeMutablePointerToElements { pointer in
            pointer.advanced(by: index).initialize(to: page)
        }
    }

    @inlinable @inline(__always)
    func withElements<R>(atPage index: Int, body: (UnsafeMutablePointer<PageBuffer<Element>?>) -> R) -> R {
        withUnsafeMutablePointerToElements { pointer in
            body(pointer.advanced(by: index))
        }
    }

    @inlinable @inline(__always)
    func removeUninitialisedLastPage(storage: inout PagedStorage<Element>, lastPageIndex: Int, lastPage: PageBuffer<Element>?) {
        withUnsafeMutablePointerToElements { pointer in
            pointer.advanced(by: lastPageIndex).deinitialize(count: 1)
        }
        storage.pageCount -= 1
    }
}
