import Testing
@testable import Components

@Suite struct SparseSetPagingTests {
    struct TestComponent: Component, Equatable {
        static let componentTag = ComponentTag.makeTag()
        var value: Int
    }

    @Test func testAppendAcrossPages() {
        var storage = PagedStorage<TestComponent>()
        let total = pageCapacity + 10
        for value in 0..<total {
            storage.pages.append(TestComponent(value: value), storage: &storage)
        }

        #expect(storage.count == total)
        #expect(storage.pageCount == 2)

        for index in 0..<total {
            #expect(storage.pages.get(index, pageCount: storage.pageCount, count: storage.count) == TestComponent(value: index))
        }
    }

    @Test func testRemoveAcrossPages() {
        var storage = PagedStorage<TestComponent>()
        let total = pageCapacity * 2
        for value in 0..<total {
            storage.pages.append(TestComponent(value: value), storage: &storage)
        }

        #expect(storage.count == pageCapacity * 2)
        #expect(storage.pageCount == 2)

        let removed = storage.pages.remove(at: pageCapacity / 2, storage: &storage)
        #expect(removed == TestComponent(value: pageCapacity / 2))
        #expect(storage.pages.get(pageCapacity / 2, pageCount: storage.pageCount, count: storage.count) == TestComponent(value: total - 1))
        #expect(storage.count == total - 1)
        #expect(storage.pageCount == 2)

        let removedCrossPage = storage.pages.remove(at: pageCapacity - 1, storage: &storage)
        #expect(removedCrossPage == TestComponent(value: pageCapacity - 1))
        #expect(storage.pages.get(pageCapacity - 1, pageCount: storage.pageCount, count: storage.count) == TestComponent(value: total - 2))
        #expect(storage.count == total - 2)

        // Removing all elements should release pages.
        while storage.count > 0 {
            storage.pages.remove(at: storage.count - 1, storage: &storage)
        }
        #expect(storage.count == 0)
        #expect(storage.pageCount == 0)
    }

    @Test func testAppendTriggersCapacityGrowth() {
        var storage = PagedStorage<TestComponent>(initialPageCapacity: 1)
        let pagesToCreate = 8
        let total = pagesToCreate * pageCapacity
        for value in 0..<total {
            storage.pages.append(TestComponent(value: value), storage: &storage)
        }
        #expect(storage.pageCount == pagesToCreate)
        #expect(storage.count == total)
        for index in stride(from: total - 1, through: 0, by: -pageCapacity) {
            #expect(storage.pages.get(index, pageCount: storage.pageCount, count: storage.count) == TestComponent(value: index))
        }
    }

    @Test func testPerformance() {
        var storage = PagedStorage<TestComponent>(initialPageCapacity: 8)
        for value in 0..<2_000_000 {
            storage.pages.append(TestComponent(value: value), storage: &storage)
        }

        let clock = ContinuousClock()
        let duration = clock.measure {
            for index in 0..<storage.count {
                storage.pages[index, storage.pageCount, storage.count].value *= -1
            }
        }
        print("Dur:", duration)

        for index in 0..<storage.count {
            #expect(storage.pages[index, storage.pageCount, storage.count].value == index * -1)
        }
    }
}
