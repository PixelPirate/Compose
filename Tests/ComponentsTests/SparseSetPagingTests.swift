import XCTest
@testable import Components

final class SparseSetPagingTests: XCTestCase {
    struct TestComponent: Component, Equatable {
        static let componentTag = ComponentTag.makeTag()
        var value: Int
    }

    func testAppendAcrossPages() {
        var storage = Storage<TestComponent>()
        let total = pageCapacity + 10
        for value in 0..<total {
            storage.pages.append(TestComponent(value: value), storage: &storage)
        }

        XCTAssertEqual(storage.count, total)
        XCTAssertEqual(storage.pageCount, 2)

        for index in 0..<total {
            XCTAssertEqual(storage.pages.get(index, storage: storage), TestComponent(value: index))
        }
    }

    func testRemoveAcrossPages() {
        var storage = Storage<TestComponent>()
        let total = pageCapacity * 2
        for value in 0..<total {
            storage.pages.append(TestComponent(value: value), storage: &storage)
        }

        XCTAssertEqual(storage.count, pageCapacity * 2)
        XCTAssertEqual(storage.pageCount, 2)

        let removed = storage.pages.remove(at: pageCapacity / 2, storage: &storage)
        XCTAssertEqual(removed, TestComponent(value: pageCapacity / 2))
        XCTAssertEqual(storage.pages.get(pageCapacity / 2, storage: storage), TestComponent(value: total - 1))
        XCTAssertEqual(storage.count, total - 1)
        XCTAssertEqual(storage.pageCount, 2)

        let removedCrossPage = storage.pages.remove(at: pageCapacity - 1, storage: &storage)
        XCTAssertEqual(removedCrossPage, TestComponent(value: pageCapacity - 1))
        XCTAssertEqual(storage.pages.get(pageCapacity - 1, storage: storage), TestComponent(value: total - 2))
        XCTAssertEqual(storage.count, total - 2)

        // Removing all elements should release pages.
        while storage.count > 0 {
            storage.pages.remove(at: storage.count - 1, storage: &storage)
        }
        XCTAssertEqual(storage.count, 0)
        XCTAssertEqual(storage.pageCount, 0)
    }

    func testAppendTriggersCapacityGrowth() {
        var storage = Storage<TestComponent>(initialPageCapacity: 1)
        let pagesToCreate = 8
        let total = pagesToCreate * pageCapacity
        for value in 0..<total {
            storage.pages.append(TestComponent(value: value), storage: &storage)
        }
        XCTAssertEqual(storage.pageCount, pagesToCreate)
        XCTAssertEqual(storage.count, total)
        for index in stride(from: total - 1, through: 0, by: -pageCapacity) {
            XCTAssertEqual(storage.pages.get(index, storage: storage), TestComponent(value: index))
        }
    }

    func testPerformance() {
        var storage = Storage<TestComponent>(initialPageCapacity: 8)
        for value in 0..<2_000_000 {
            storage.pages.append(TestComponent(value: value), storage: &storage)
        }

        let clock = ContinuousClock()
        let duration = clock.measure {
            for index in 0..<storage.count {
                storage.pages[index, storage].value *= -1
            }
        }
        print("Dur:", duration)

        for index in 0..<storage.count {
            XCTAssertEqual(storage.pages[index, storage].value, index * -1)
        }
    }
}
