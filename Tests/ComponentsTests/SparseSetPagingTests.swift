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
            storage.append(TestComponent(value: value))
        }

        #expect(storage.count == total)
        #expect(storage.pageCount == 2)

        for index in 0..<total {
            #expect(storage[index] == TestComponent(value: index))
        }
    }

    @Test func testRemoveAcrossPages() {
        var storage = PagedStorage<TestComponent>()
        let total = pageCapacity * 2
        for value in 0..<total {
            storage.append(TestComponent(value: value))
        }

        #expect(storage.count == pageCapacity * 2)
        #expect(storage.pageCount == 2)

        let removed = storage.remove(at: pageCapacity / 2)
        #expect(removed == TestComponent(value: pageCapacity / 2))
        #expect(storage[pageCapacity / 2] == TestComponent(value: total - 1))
        #expect(storage.count == total - 1)
        #expect(storage.pageCount == 2)

        let removedCrossPage = storage.remove(at: pageCapacity - 1)
        #expect(removedCrossPage == TestComponent(value: pageCapacity - 1))
        #expect(storage[pageCapacity - 1] == TestComponent(value: total - 2))
        #expect(storage.count == total - 2)

        // Removing all elements should release pages.
        while storage.count > 0 {
            _ = storage.remove(at: storage.count - 1)
        }
        #expect(storage.count == 0)
        #expect(storage.pageCount == 0)
    }

    @Test func testAppendTriggersCapacityGrowth() {
        var storage = PagedStorage<TestComponent>(initialPageCapacity: 1)
        let pagesToCreate = 8
        let total = pagesToCreate * pageCapacity
        for value in 0..<total {
            storage.append(TestComponent(value: value))
        }
        #expect(storage.pageCount == pagesToCreate)
        #expect(storage.count == total)
        for index in stride(from: total - 1, through: 0, by: -pageCapacity) {
            #expect(storage[index] == TestComponent(value: index))
        }
    }

    @Test func testPerformance() {
        var storage = PagedStorage<TestComponent>(initialPageCapacity: 8)
        for value in 0..<2_000_000 {
            storage.append(TestComponent(value: value))
        }

        let clock = ContinuousClock()
        let duration = clock.measure {
            for index in 0..<storage.count {
                storage[index].value *= -1
            }
        }
        print("Dur:", duration)

        for index in 0..<storage.count {
            #expect(storage[index].value == index * -1)
        }
    }
}
