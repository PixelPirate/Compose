
@usableFromInline
let defaultInitialPageCapacity = 1

    public struct Storage<Component> {
        public var count: Int

        public var pageCount: Int

        public var pages: PagesBuffer<Component>

        @inlinable
        public init(initialPageCapacity: Int = defaultInitialPageCapacity) {
            precondition(initialPageCapacity > 0)
            self.count = 0
            self.pageCount = 0
            self.pages = PagesBuffer.create(initialCapacity: initialPageCapacity)
        }
    }
@usableFromInline
let pageShift = 10

@usableFromInline
let pageCapacity = 1 << pageShift

@usableFromInline
let pageMask = pageCapacity - 1

    public final class ComponentPageBuffer<Component>: ManagedBuffer<Void, Component> {
        @inlinable
        static func createPage() -> ComponentPageBuffer {
            unsafeDowncast(Self.create(minimumCapacity: pageCapacity) { _ in () }, to: Self.self)
        }

        @inlinable
        func initializeElement(at index: Int, to value: Component) {
            precondition(index < pageCapacity)
            withUnsafeMutablePointerToElements { buffer in
                buffer.advanced(by: index).initialize(to: value)
            }
        }

        @inlinable
        func moveInitializeElement(at index: Int, from other: ComponentPageBuffer, sourceIndex: Int) {
            precondition(index < pageCapacity)
            precondition(sourceIndex < pageCapacity)
            withUnsafeMutablePointerToElements { destination in
                other.withUnsafeMutablePointerToElements { source in
                    destination.advanced(by: index).moveInitialize(from: source.advanced(by: sourceIndex), count: 1)
                }
            }
        }

        @inlinable
        func moveElement(at index: Int) -> Component {
            precondition(index < pageCapacity)
            return withUnsafeMutablePointerToElements { buffer in
                buffer.advanced(by: index).move()
            }
        }

        @inlinable
        func value(at index: Int) -> Component {
            precondition(index < pageCapacity)
            return withUnsafeMutablePointerToElements { buffer in
                buffer[index]
            }
        }

        @inlinable
        subscript(index: Int) -> Component {
            @inlinable
            _read {
                precondition(index < pageCapacity)
                yield withUnsafeMutablePointerToElements { buffer in
                    buffer[index]
                }
            }
            @inlinable
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


        @inlinable
        static func create(initialCapacity: Int = defaultInitialCapacity) -> PagesBuffer {
            precondition(initialCapacity > 0)
            return unsafeDowncast(Self.create(minimumCapacity: initialCapacity) { _ in () }, to: Self.self)
        }

        @inlinable @discardableResult
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

            let page = buffer.page(at: pageIndex)
            page.initializeElement(at: offset, to: component)
            storage.count = nextIndex + 1
            return nextIndex
        }

        @inlinable
        func get(_ index: Int, storage: Storage<Component>) -> Component {
            precondition(self === storage.pages)
            precondition(index < storage.count)
            let pageIndex = index >> pageShift
            let offset = index & pageMask
            precondition(pageIndex < storage.pageCount)
            let page = page(at: pageIndex)
            return page.value(at: offset)
        }

        @inlinable
        public subscript(_ index: Int, storage: Storage<Component>) -> Component {
            @inlinable
            _read {
                yield get(index, storage: storage)
            }
            @inlinable
            _modify {
                precondition(self === storage.pages)
                precondition(index < storage.count)
                let pageIndex = index >> pageShift
                let offset = index & pageMask
                precondition(pageIndex < storage.pageCount)
                let page = page(at: pageIndex)
                yield &page[offset]
            }
        }

        @inlinable
        @discardableResult
        func remove(at index: Int, storage: inout Storage<Component>) -> Component {
            precondition(self === storage.pages)
            precondition(index < storage.count)

            let lastIndex = storage.count - 1
            let lastPageIndex = lastIndex >> pageShift
            let lastOffset = lastIndex & pageMask
            let pageIndex = index >> pageShift
            let offset = index & pageMask

            let page = page(at: pageIndex)
            let removed = page.moveElement(at: offset)

            if index != lastIndex {
                let lastPage = self.page(at: lastPageIndex)
                page.moveInitializeElement(at: offset, from: lastPage, sourceIndex: lastOffset)
            }

            storage.count = lastIndex

            if lastOffset == 0 {
                let lastPage = self.page(at: lastPageIndex)
                removeUninitialisedLastPage(storage: &storage, lastPageIndex: lastPageIndex, lastPage: lastPage)
            }

            return removed
        }

        @inlinable
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

        @inlinable
        func initializePage(_ page: ComponentPageBuffer<Component>, at index: Int) {
            withUnsafeMutablePointerToElements { pointer in
                pointer.advanced(by: index).initialize(to: page)
            }
        }

        @inlinable
        func page(at index: Int) -> ComponentPageBuffer<Component> {
            withUnsafeMutablePointerToElements { pointer in
                pointer[index]
            }
        }

        @inlinable
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
