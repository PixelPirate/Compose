import XCTest
@testable import Components

final class SparseSetPagingTests: XCTestCase {
    typealias TestSparseSet = SparseSet<Int, Array.Index>
    typealias Storage = TestSparseSet.Storage
    typealias PageBuffer = TestSparseSet.ComponentPageBuffer

    func testAppendAcrossPages() {
        var storage = Storage()
        let total = PageBuffer.pageCapacity + 10
        for value in 0..<total {
            storage.pages.append(value, storage: &storage)
        }

        XCTAssertEqual(storage.count, total)
        XCTAssertEqual(storage.pageCount, 2)

        for index in 0..<total {
            XCTAssertEqual(storage.pages.get(index, storage: storage), index)
        }
    }

    func testRemoveAcrossPages() {
        var storage = Storage()
        let total = PageBuffer.pageCapacity * 2
        for value in 0..<total {
            storage.pages.append(value, storage: &storage)
        }

        XCTAssertEqual(storage.pageCount, 2)

        let removed = storage.pages.remove(PageBuffer.pageCapacity / 2, storage: &storage)
        XCTAssertEqual(removed, PageBuffer.pageCapacity / 2)
        XCTAssertEqual(storage.count, total - 1)
        XCTAssertEqual(storage.pageCount, 2)

        let removedCrossPage = storage.pages.remove(PageBuffer.pageCapacity - 1, storage: &storage)
        XCTAssertNotEqual(removedCrossPage, PageBuffer.pageCapacity - 1)
        XCTAssertEqual(storage.count, total - 2)

        // Removing all elements should release pages.
        while storage.count > 0 {
            storage.pages.remove(storage.count - 1, storage: &storage)
        }
        XCTAssertEqual(storage.count, 0)
        XCTAssertEqual(storage.pageCount, 0)
    }

    func testAppendTriggersCapacityGrowth() {
        var storage = Storage(initialPageCapacity: 1)
        let pagesToCreate = 8
        let total = pagesToCreate * PageBuffer.pageCapacity
        for value in 0..<total {
            storage.pages.append(value, storage: &storage)
        }
        XCTAssertEqual(storage.pageCount, pagesToCreate)
        XCTAssertEqual(storage.count, total)
        for index in stride(from: total - 1, through: 0, by: -PageBuffer.pageCapacity) {
            XCTAssertEqual(storage.pages.get(index, storage: storage), index)
        }
    }
}
