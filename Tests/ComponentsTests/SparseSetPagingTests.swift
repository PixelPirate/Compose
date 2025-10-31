import Testing
@testable import Components

@Suite struct SparseSetPagingTests {
    struct TestComponent: Component, Equatable {
        static let componentTag = ComponentTag.makeTag()
        var value: Int
    }

    @Test func testAppendAcrossPages() {
        var storage = SparseSet<TestComponent, Int>()
        let total = PagedSlotToDenseConstants.pageSize + 10
        storage.ensureEntity(total - 1)
        for value in 0..<total {
            storage.append(TestComponent(value: value), to: value)
        }

        #expect(storage.count == total)
        #expect(storage.slotPages == 2)

        for index in 0..<total {
            #expect(storage[index] == TestComponent(value: index))
        }
    }

    @Test func testRemoveAcrossSparsePages() {
        var storage = SparseSet<TestComponent, Int>()
        let total = PagedSlotToDenseConstants.pageSize * 2
        storage.ensureEntity(total - 1)

        #expect(storage.slots.values.liveCounts[0] == 0)
        #expect(storage.slots.values.liveCounts[1] == 0)

        for value in 0..<total {
            storage.append(TestComponent(value: value), to: value)
        }

        #expect(storage.count == PagedSlotToDenseConstants.pageSize * 2)
        #expect(storage.slotPages == 2)
        #expect(storage.liveSlotPages == 2)
        #expect(storage.slots.values.liveCounts[0] == 4096)
        #expect(storage.slots.values.liveCounts[1] == 4096)

        let removedFirstOnLastPage = storage.remove(PagedSlotToDenseConstants.pageSize)
        #expect(removedFirstOnLastPage == TestComponent(value: PagedSlotToDenseConstants.pageSize))
        #expect(storage[PagedSlotToDenseConstants.pageSize] == TestComponent(value: total - 1))
        #expect(storage.count == total - 1)
        #expect(storage.slotPages == 2)
        #expect(storage.liveSlotPages == 2)
        #expect(storage.slots.values.liveCounts[0] == 4096)
        #expect(storage.slots.values.liveCounts[1] == 4095)

        let removedCrossPage = storage.remove(PagedSlotToDenseConstants.pageSize - 1)
        #expect(removedCrossPage == TestComponent(value: PagedSlotToDenseConstants.pageSize - 1))
        #expect(storage[PagedSlotToDenseConstants.pageSize - 1] == TestComponent(value: total - 2))
        #expect(storage.count == total - 2)
        #expect(storage.slotPages == 2)
        #expect(storage.liveSlotPages == 2)
        #expect(storage.slots.values.liveCounts[0] == 4095)
        #expect(storage.slots.values.liveCounts[1] == 4095)

        // Removing all elements should release pages.
        while let slot = storage.keys.last {
            _ = storage.remove(slot)
        }
        #expect(storage.count == 0)
        #expect(storage.keys.isEmpty)
        #expect(storage.liveSlotPages == 0)
        #expect(storage.slotPages == 2)
    }

    @Test func testAppendTriggersCapacityGrowth() {
        var storage = SparseSet<TestComponent, Int>()
        let pagesToCreate = 8
        let total = pagesToCreate * PagedSlotToDenseConstants.pageSize
        storage.ensureEntity(total - 1)
        for value in 0..<total {
            storage.append(TestComponent(value: value), to: value)
        }
        #expect(storage.slotPages == pagesToCreate)
        #expect(storage.count == total)
        for index in stride(from: total - 1, through: 0, by: -PagedSlotToDenseConstants.pageSize) {
            #expect(storage[index] == TestComponent(value: index))
        }
    }

    @Test func testPerformance() {
        var storage = SparseSet<TestComponent, Int>()
        storage.ensureEntity(1_999_999)
        for value in 0..<2_000_000 {
            storage.append(TestComponent(value: value), to: value)
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
