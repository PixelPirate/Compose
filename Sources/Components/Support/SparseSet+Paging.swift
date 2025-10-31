import Synchronization

@usableFromInline
internal enum SlotsSpanConstants {
    @usableFromInline
    static let pageShift = 12

    @usableFromInline
    static let pageSize = 1 << pageShift // 4096

    @usableFromInline
    static let pageMask = pageSize - 1
}

public struct SlotsSpan<Dense: SparseArrayValue, Slot: SparseSetIndex> {
    @usableFromInline
    let pages: UnsafeBufferPointer<UnsafePointer<Dense>>

    @inlinable @inline(__always)
    init(view base: UnsafeMutableBufferPointer<UnsafeMutablePointer<Dense>>) {
        pages = UnsafeBufferPointer(
            base.withMemoryRebound(to: UnsafePointer<Dense>.self) { $0 }
        )
    }

    @inlinable @inline(__always)
    public subscript(slot: Slot) -> Dense {
        @_transparent
        unsafeAddress {
            let page = slot.index >> SlotsSpanConstants.pageShift
            let offset = slot.index & SlotsSpanConstants.pageMask
            return UnsafePointer(pages[page].advanced(by: offset))
        }
    }

    @inlinable @inline(__always)
    public subscript(checked slot: Slot) -> Dense {
        @_transparent
        _read {
            guard pages.baseAddress != nil else {
                yield .notFound
                return
            }
            let page = slot.index >> SlotsSpanConstants.pageShift
            let offset = slot.index & SlotsSpanConstants.pageMask
            yield pages[page].advanced(by: offset).pointee
        }
    }
}

@usableFromInline
enum PagedSlotToDenseConstants {
    @usableFromInline
    static let emptyPages: Mutex<[ObjectIdentifier: UnsafeMutableRawPointer]> = Mutex([:])

    @usableFromInline
    static func getEmpty<T>(_ t: T.Type, default: @autoclosure () -> UnsafeMutablePointer<T>) -> UnsafeMutablePointer<T> {
        emptyPages.withLock {
            if let existing = $0[ObjectIdentifier(t)] {
                return existing.assumingMemoryBound(to: T.self)
            } else {
                let new = `default`()
                $0[ObjectIdentifier(T.self)] = UnsafeMutableRawPointer(new)
                return new
            }
        }
    }

    @usableFromInline
    static let pageShift = 12

    @usableFromInline
    static let pageSize = 1 << pageShift // 4096

    @usableFromInline
    static let pageMask = pageSize - 1
}

@usableFromInline
struct PagedSlotToDense<Dense: SparseArrayValue, Slot: SparseSetIndex> {
    @usableFromInline
    var pages: UnsafeMutableBufferPointer<UnsafeMutablePointer<Dense>>

    @usableFromInline
    var liveCounts: UnsafeMutableBufferPointer<Int>

    @usableFromInline
    let emptyPage: UnsafeMutablePointer<Dense>

    @inlinable @inline(__always)
    init() {
        emptyPage = PagedSlotToDenseConstants.getEmpty(Dense.self, default: Self.makeEmptyPage())

        pages = .allocate(capacity: 1)
        pages.initialize(repeating: emptyPage)

        liveCounts = .allocate(capacity: 1)
        liveCounts.initialize(repeating: 0)
    }

    @inlinable @_transparent
    var view: SlotsSpan<Dense, Slot> {
        _read {
            yield SlotsSpan(view: pages)
        }
    }

    @inlinable @inline(__always)
    var count: Int {
        pages.count * PagedSlotToDenseConstants.pageSize
    }

    @inlinable @inline(__always)
    func deallocate() {
        for page in pages where page != emptyPage {
            page.deallocate()
        }
        pages.deallocate()
        liveCounts.deallocate()
    }

    @inlinable @inline(__always)
    mutating func ensureCapacity(forSlot slot: Slot) {
        let requiredPage = slot.index >> PagedSlotToDenseConstants.pageShift
        ensureCapacity(forPage: requiredPage)
    }

    @inlinable @inline(__always)
    mutating func ensureCapacity(forPage requiredPage: Int) {
        if requiredPage >= pages.count {
            let newCount = requiredPage &+ 1
            let newPages = UnsafeMutableBufferPointer<UnsafeMutablePointer<Dense>>.allocate(capacity: newCount)
            let uninitialisedIndex = newPages.moveInitialize(fromContentsOf: pages)
            newPages
                .baseAddress
                .unsafelyUnwrapped
                .advanced(by: uninitialisedIndex)
                .initialize(
                    repeating: emptyPage,
                    count: newCount - uninitialisedIndex
                )
            pages.deallocate()
            pages = newPages

            let newLive = UnsafeMutableBufferPointer<Int>.allocate(capacity: newCount)
            let uninitialisedLiveIndex = newLive.moveInitialize(fromContentsOf: liveCounts)
            newLive
                .baseAddress
                .unsafelyUnwrapped
                .advanced(by: uninitialisedLiveIndex)
                .initialize(repeating: 0, count: newCount - uninitialisedIndex)
            liveCounts.deallocate()
            liveCounts = newLive
        }
    }

    @inlinable @_transparent
    func pointer(for slot: Slot) -> UnsafePointer<Dense> {
        let page = slot.index >> PagedSlotToDenseConstants.pageShift
        let offset = slot.index & PagedSlotToDenseConstants.pageMask
        precondition(page < pages.count, "Page \(page) is out of bounds.")
        return UnsafePointer(pages[page].advanced(by: offset))
    }

    @inlinable @inline(__always)
    subscript(slot: Slot) -> Dense {
        @_transparent
        unsafeAddress {
            pointer(for: slot)
        }

        @_transparent
        mutating _modify {
            let pageIndex = slot.index >> PagedSlotToDenseConstants.pageShift
            let offset = slot.index & PagedSlotToDenseConstants.pageMask
            precondition(pageIndex < pages.count, "Page \(pageIndex) is out of bounds.")

            var page = pages[pageIndex]
            if page == emptyPage {
                let newPage = Self.makeEmptyPage()
                pages[pageIndex] = newPage
                page = newPage
            }

            let pointer = page.advanced(by: offset)
            let oldValue = pointer.pointee
            yield &pointer.pointee
            let newValue = pointer.pointee

            if oldValue == .notFound, newValue != .notFound {
                liveCounts[pageIndex] &+= 1
            } else if oldValue != .notFound, newValue == .notFound {
                liveCounts[pageIndex] &-= 1
                if liveCounts[pageIndex] == 0 {
                    pages[pageIndex] = emptyPage
                    page.deallocate()
                }
            } else if oldValue == .notFound, newValue == .notFound, liveCounts[pageIndex] == 0 {
                pages[pageIndex] = emptyPage
                page.deallocate()
            }
        }
    }

    @inlinable @inline(__always)
    static func makeEmptyPage() -> UnsafeMutablePointer<Dense> {
        let page = UnsafeMutablePointer<Dense>.allocate(capacity: PagedSlotToDenseConstants.pageSize)
        page.initialize(repeating: .notFound, count: PagedSlotToDenseConstants.pageSize)
        return page
    }

    @inlinable
    var liveCount: Int {
        var count = 0
        for page in liveCounts where page > 0 {
            count += 1
        }
        return count
    }
}
