extension SparseSet {
    @usableFromInline
    struct Storage {
        @usableFromInline
        internal static let defaultInitialPageCapacity = 1

        @usableFromInline
        internal var count: Int

        @usableFromInline
        internal var pageCount: Int

        @usableFromInline
        internal var pages: PagesBuffer

        @inlinable
        init(initialPageCapacity: Int = Self.defaultInitialPageCapacity) {
            precondition(initialPageCapacity > 0)
            self.count = 0
            self.pageCount = 0
            self.pages = PagesBuffer.create(initialCapacity: initialPageCapacity)
        }
    }

    @usableFromInline
    final class ComponentPageBuffer: ManagedBuffer<Void, Component> {
        @usableFromInline
        internal static let pageShift = 10

        @usableFromInline
        internal static let pageCapacity = 1 << pageShift

        @usableFromInline
        internal static let pageMask = pageCapacity - 1

        @inlinable
        static func createPage() -> ComponentPageBuffer {
            Self.create(minimumCapacity: pageCapacity) { _ in () }
        }

        @inlinable
        func initializeElement(at index: Int, to value: Component) {
            precondition(index < Self.pageCapacity)
            withUnsafeMutablePointerToElements { buffer in
                buffer.advanced(by: index).initialize(to: value)
            }
        }

        @inlinable
        func moveInitializeElement(at index: Int, from other: ComponentPageBuffer, sourceIndex: Int) {
            precondition(index < Self.pageCapacity)
            precondition(sourceIndex < Self.pageCapacity)
            withUnsafeMutablePointerToElements { destination in
                other.withUnsafeMutablePointerToElements { source in
                    destination.advanced(by: index).moveInitialize(from: source.advanced(by: sourceIndex), count: 1)
                }
            }
        }

        @inlinable
        func moveElement(at index: Int) -> Component {
            precondition(index < Self.pageCapacity)
            return withUnsafeMutablePointerToElements { buffer in
                buffer.advanced(by: index).move()
            }
        }

        @inlinable
        func value(at index: Int) -> Component {
            precondition(index < Self.pageCapacity)
            return withUnsafeMutablePointerToElements { buffer in
                buffer[index]
            }
        }
    }

    @usableFromInline
    final class PagesBuffer: ManagedBuffer<Void, ComponentPageBuffer> {
        @usableFromInline
        internal static let defaultInitialCapacity = 1

        @inlinable
        static func create(initialCapacity: Int = defaultInitialCapacity) -> PagesBuffer {
            precondition(initialCapacity > 0)
            return Self.create(minimumCapacity: initialCapacity) { _ in () }
        }

        @inlinable
        func append(_ component: Component, storage: inout Storage) -> Int {
            precondition(self === storage.pages)

            var buffer: PagesBuffer = self
            let nextIndex = storage.count
            let pageIndex = nextIndex >> ComponentPageBuffer.pageShift
            let offset = nextIndex & ComponentPageBuffer.pageMask

            if pageIndex == storage.pageCount {
                buffer = buffer.ensureCapacity(forPageCount: storage.pageCount + 1, storage: &storage)
                let newPage = ComponentPageBuffer.createPage()
                buffer.initializePage(newPage, at: pageIndex)
                storage.pageCount += 1
            }

            let page = buffer.page(at: pageIndex)
            page.initializeElement(at: offset, to: component)
            storage.count = nextIndex + 1
            return nextIndex
        }

        @inlinable
        func get(_ index: Int, storage: Storage) -> Component {
            precondition(self === storage.pages)
            precondition(index < storage.count)
            let pageIndex = index >> ComponentPageBuffer.pageShift
            let offset = index & ComponentPageBuffer.pageMask
            precondition(pageIndex < storage.pageCount)
            let page = page(at: pageIndex)
            return page.value(at: offset)
        }

        @inlinable
        @discardableResult
        func remove(at index: Int, storage: inout Storage) -> Component {
            precondition(self === storage.pages)
            precondition(index < storage.count)

            let lastIndex = storage.count - 1
            let lastPageIndex = lastIndex >> ComponentPageBuffer.pageShift
            let lastOffset = lastIndex & ComponentPageBuffer.pageMask
            let pageIndex = index >> ComponentPageBuffer.pageShift
            let offset = index & ComponentPageBuffer.pageMask

            let page = page(at: pageIndex)
            let removed = page.moveElement(at: offset)

            if index != lastIndex {
                let lastPage = page(at: lastPageIndex)
                page.moveInitializeElement(at: offset, from: lastPage, sourceIndex: lastOffset)
            }

            storage.count = lastIndex

            if lastOffset == 0 {
                let lastPage = page(at: lastPageIndex)
                removeLastPage(storage: &storage, lastPageIndex: lastPageIndex, lastPage: lastPage)
            }

            return removed
        }

        @inlinable
        private func ensureCapacity(forPageCount requiredPageCount: Int, storage: inout Storage) -> PagesBuffer {
            if requiredPageCount <= capacity {
                return self
            }

            let newCapacity = Swift.max(capacity << 1, requiredPageCount)
            let newBuffer = PagesBuffer.create(initialCapacity: newCapacity)
            let existingPageCount = storage.pageCount
            withUnsafeMutablePointerToElements { source in
                newBuffer.withUnsafeMutablePointerToElements { destination in
                    destination.initialize(from: source, count: existingPageCount)
                }
                source.deinitialize(count: existingPageCount)
            }
            self.deallocate()
            storage.pages = newBuffer
            return newBuffer
        }

        @inlinable
        private func initializePage(_ page: ComponentPageBuffer, at index: Int) {
            withUnsafeMutablePointerToElements { pointer in
                pointer.advanced(by: index).initialize(to: page)
            }
        }

        @inlinable
        private func page(at index: Int) -> ComponentPageBuffer {
            withUnsafeMutablePointerToElements { pointer in
                pointer[index]
            }
        }

        @inlinable
        private func removeLastPage(storage: inout Storage, lastPageIndex: Int, lastPage: ComponentPageBuffer) {
            withUnsafeMutablePointerToElements { pointer in
                pointer.advanced(by: lastPageIndex).deinitialize(count: 1)
            }
            storage.pageCount -= 1
            lastPage.deallocate()
        }
    }
}
