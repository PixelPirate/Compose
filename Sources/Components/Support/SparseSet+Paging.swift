
@usableFromInline
let defaultInitialPageCapacity = 1

public struct UnmanagedStorage<Component> {
    public var count: Int

    public var pageCount: Int

    public var pages: Unmanaged<PagesBuffer<Component>>

    @inlinable @inline(__always)
    public init(_ storage: Storage<Component>) {
        self.count = storage.count
        self.pageCount = storage.pageCount
        self.pages = .passUnretained(storage.pages)
    }

    @inlinable @inline(__always)
    public init(_ pages: Unmanaged<PagesBuffer<Component>>, count: Int, pageCount: Int) {
        self.count = count
        self.pageCount = pageCount
        self.pages = pages
    }

    @inlinable @inline(__always)
    public subscript(_ index: Int) -> Component {
        @inlinable @inline(__always)
        _read {
            yield pages.takeUnretainedValue()[index, pageCount, count]
        }
        @inlinable @inline(__always)
        nonmutating _modify {
            yield &pages.takeUnretainedValue()[index, pageCount, count]
        }
    }

    @inlinable @inline(__always)
    public func elementPointer(_ index: Int) -> UnsafeMutablePointer<Component> {
        pages.takeUnretainedValue().getPointer(index, pageCount: pageCount, count: count)
    }
}

public struct Storage<Component> {
    public var count: Int

    public var pageCount: Int

    public var pages: PagesBuffer<Component>

    @inlinable @inline(__always)
    public init(initialPageCapacity: Int = defaultInitialPageCapacity) {
        precondition(initialPageCapacity > 0)
        self.count = 0
        self.pageCount = 0
        self.pages = PagesBuffer.create(initialCapacity: initialPageCapacity)
    }

    @inlinable @inline(__always)
    public subscript(_ index: Int) -> Component {
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
    public mutating func append(_ component: Component) {
        pages.append(component, storage: &self)
    }

    @inlinable @inline(__always) @discardableResult
    public mutating func removeLast() -> Component {
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

public let pageShift = 10 // 10 -> 1024, 20 -> 1M

public let pageCapacity = 1 << pageShift

public let pageMask = pageCapacity - 1

    public final class ComponentPageBuffer<Component>: ManagedBuffer<Void, Component> {
        @inlinable @inline(__always)
        static func createPage() -> ComponentPageBuffer {
            unsafeDowncast(Self.create(minimumCapacity: pageCapacity) { _ in () }, to: Self.self)
        }

        @inlinable @inline(__always)
        func initializeElement(at index: Int, to value: Component) {
            precondition(index < pageCapacity)
            withUnsafeMutablePointerToElements { buffer in
                buffer.advanced(by: index).initialize(to: value)
            }
        }

        @inlinable @inline(__always)
        func moveInitializeElement(at index: Int, from other: ComponentPageBuffer, sourceIndex: Int) {
            precondition(index < pageCapacity)
            precondition(sourceIndex < pageCapacity)
            withUnsafeMutablePointerToElements { destination in
                other.withUnsafeMutablePointerToElements { source in
                    destination.advanced(by: index).moveInitialize(from: source.advanced(by: sourceIndex), count: 1)
                }
            }
        }

        @inlinable @inline(__always)
        func moveElement(at index: Int) -> Component {
            precondition(index < pageCapacity)
            return withUnsafeMutablePointerToElements { buffer in
                buffer.advanced(by: index).move()
            }
        }

        @inlinable @inline(__always)
        func value(at index: Int) -> Component {
            precondition(index < pageCapacity)
            return withUnsafeMutablePointerToElements { buffer in
                buffer[index]
            }
        }

        @inlinable @inline(__always)
        subscript(index: Int) -> Component {
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

@usableFromInline
let defaultInitialCapacity = 1

    public final class PagesBuffer<Component>: ManagedBuffer<Void, ComponentPageBuffer<Component>> {
        @inlinable @inline(__always)
        static func create(initialCapacity: Int = defaultInitialCapacity) -> PagesBuffer {
            precondition(initialCapacity > 0)
            return unsafeDowncast(Self.create(minimumCapacity: initialCapacity) { _ in () }, to: Self.self)
        }

        @inlinable @inline(__always) @discardableResult
        public func append(_ component: Component, storage: inout Storage<Component>) -> Int {
            precondition(self === storage.pages)

            var buffer: PagesBuffer = self
            let nextIndex = storage.count
            let pageIndex = nextIndex >> pageShift
            let offset = nextIndex & pageMask

            if pageIndex == storage.pageCount {
                buffer = buffer.ensureCapacity(forPageCount: storage.pageCount + 1, storage: &storage)
                let newPage = ComponentPageBuffer<Component>.createPage()
                buffer.initializePage(newPage, at: pageIndex)
                storage.pageCount += 1
            }

            buffer.withElements(atPage: pageIndex) { pointer in
                pointer.pointee.initializeElement(at: offset, to: component)
            }
            storage.count = nextIndex + 1
            return nextIndex
        }

        @inlinable @inline(__always)
        func get(_ index: Int, pageCount: Int, count: Int) -> Component {
            precondition(index < count)
            let pageIndex = index >> pageShift
            let offset = index & pageMask
            precondition(pageIndex < pageCount)
            return withElements(atPage: pageIndex) { pagePointer in
                pagePointer.pointee.withUnsafeMutablePointerToElements { elementsPointer in
                    elementsPointer.advanced(by: offset).pointee
                }
            }
        }

        @inlinable @inline(__always)
        public func getPointer(_ index: Int, pageCount: Int, count: Int) -> UnsafeMutablePointer<Component> {
            precondition(index < count)
            let pageIndex = index >> pageShift
            let offset = index & pageMask
            precondition(pageIndex < pageCount)
            return withElements(atPage: pageIndex) { pagePointer in
                pagePointer.pointee.withUnsafeMutablePointerToElements { elementsPointer in
                    elementsPointer.advanced(by: offset)
                }
            }
        }

        @inlinable @inline(__always)
        public subscript(_ index: Int, pageCount: Int, count: Int) -> Component {
            @inlinable @inline(__always)
            _read {
                yield get(index, pageCount: pageCount, count: count)
            }
            @inlinable @inline(__always)
            _modify {
                let pageIndex = index >> pageShift
                let offset = index & pageMask

                let pointer = withUnsafeMutablePointerToElements { pagesPointer in
                    pagesPointer[pageIndex].withUnsafeMutablePointerToElements { elementsPointer in
                        elementsPointer.advanced(by: offset)
                    }
                }
                yield &pointer.pointee
//                precondition(index < count)
//                let pageIndex = index >> pageShift
//                let offset = index & pageMask
//                precondition(pageIndex < pageCount)
//                let page = page(at: pageIndex)
//                yield &page[offset]
            }
        }

        @inlinable @inline(__always)
        @discardableResult
        func remove(at index: Int, storage: inout Storage<Component>) -> Component {
            precondition(self === storage.pages)
            precondition(index < storage.count)

            let lastIndex = storage.count - 1
            let lastPageIndex = lastIndex >> pageShift
            let lastOffset = lastIndex & pageMask
            let pageIndex = index >> pageShift
            let offset = index & pageMask

            let page = withElements(atPage: pageIndex, body: \.pointee)
            let removed = page.moveElement(at: offset)

            if index != lastIndex {
                let lastPage = withElements(atPage: lastPageIndex, body: \.pointee)
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
        func ensureCapacity(forPageCount requiredPageCount: Int, storage: inout Storage<Component>) -> PagesBuffer {
            if requiredPageCount <= capacity {
                return self
            }

            let newCapacity = Swift.max(capacity << 1, requiredPageCount)
            let newBuffer = PagesBuffer.create(initialCapacity: newCapacity)
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
        func initializePage(_ page: ComponentPageBuffer<Component>, at index: Int) {
            withUnsafeMutablePointerToElements { pointer in
                pointer.advanced(by: index).initialize(to: page)
            }
        }

        @inlinable @inline(__always)
        func withElements<R>(atPage index: Int, body: (UnsafeMutablePointer<ComponentPageBuffer<Component>>) -> R) -> R {
            withUnsafeMutablePointerToElements { pointer in
                body(pointer.advanced(by: index))
            }
        }

        @inlinable @inline(__always)
        func removeUninitialisedLastPage(storage: inout Storage<Component>, lastPageIndex: Int, lastPage: ComponentPageBuffer<Component>) {
            withUnsafeMutablePointerToElements { pointer in
                let lastPage = pointer.advanced(by: lastPageIndex)
//                lastPage.pointee.withUnsafeMutablePointerToElements { elements in
//                    elements.deallocate()
//                }
                // I don't think I need to deallocate anything, this should be done by ManagedBuffer.
                lastPage.deinitialize(count: 1)
            }
            storage.pageCount -= 1
        }
    }
