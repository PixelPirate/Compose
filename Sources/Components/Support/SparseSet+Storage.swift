//
//  UnmanagedPagedStorage.swift
//  Components
//
//  Created by Patrick Horlebein on 27.10.25.
//


//@usableFromInline
//let defaultInitialPageCapacity = 1
//
//@usableFromInline
//let defaultInitialCapacity = 1
//
//public let pageShift = 10 // 10 -> 1024, 20 -> 1M
//
//public let pageCapacity = 1 << pageShift
//
//public let pageMask = pageCapacity - 1

public struct UnmanagedContiguousStorage<Element> {
    public var count: Int
    public var buffer: Unmanaged<ContiguousBuffer<Element>>

    @inlinable @inline(__always)
    public init(_ storage: ContiguousStorage<Element>) {
        self.count = storage.count
        self.buffer = .passUnretained(storage.buffer)
    }

    @inlinable @inline(__always)
    public init(_ pages: Unmanaged<ContiguousBuffer<Element>>, count: Int) {
        self.count = count
        self.buffer = pages
    }

    @inlinable @inline(__always)
    public subscript(_ index: Int) -> Element {
        @inlinable @inline(__always)
        _read {
            yield buffer.takeUnretainedValue()[index]
        }
        @inlinable @inline(__always)
        nonmutating _modify {
            yield &buffer.takeUnretainedValue()[index]
        }
    }

    @inlinable @inline(__always)
    public func elementPointer(_ index: Int) -> UnsafeMutablePointer<Element> {
//        pages.takeUnretainedValue().getPointer(index, pageCount: pageCount, count: count)
        buffer._withUnsafeGuaranteedRef { x in
            x.getPointer(index, count: count)
        }
    }
}

public struct ContiguousStorage<Element> {
    public var count: Int
    public var capacity: Int
    public var buffer: ContiguousBuffer<Element>

    @inlinable @inline(__always)
    public init(initialPageCapacity: Int = 1024) {
        precondition(initialPageCapacity > 0)
        self.count = 0
        self.capacity = initialPageCapacity
        self.buffer = ContiguousBuffer.create(initialCapacity: initialPageCapacity)
    }

    @inlinable @inline(__always)
    public subscript(_ index: Int) -> Element {
        @inlinable
        _read {
            yield buffer[index]
        }
        @inlinable
        _modify {
            yield &buffer[index]
        }
    }

    @inlinable @inline(__always)
    public mutating func append(_ component: Element) {
        buffer.append(component, storage: &self)
    }

    @inlinable @inline(__always) @discardableResult
    public mutating func removeLast() -> Element {
        precondition(count > 0)
        return buffer.remove(at: count - 1, storage: &self)
    }

    @inlinable @inline(__always)
    public mutating func swapAt(_ i: Int, _ j: Int) {
        precondition(i != j)
        buffer.withUnsafeMutablePointerToElements { elementsPointer in
            let iValue = elementsPointer.advanced(by: i).move()
            elementsPointer.moveInitialize(from: elementsPointer.advanced(by: j), count: 1)
            elementsPointer.advanced(by: j).initialize(to: iValue)
        }
    }
}

public final class ContiguousBuffer<Element>: ManagedBuffer<Void, Element> {
    @inlinable @inline(__always)
    static func create(initialCapacity: Int) -> Self {
        precondition(initialCapacity > 0)
        return unsafeDowncast(ContiguousBuffer.create(minimumCapacity: initialCapacity) { _ in () }, to: Self.self)
    }

    @inlinable @inline(__always)
    func moveInitializeElement(at index: Int, sourceIndex: Int) {
//        precondition(index < pageCapacity)
//        precondition(sourceIndex < pageCapacity)
        withUnsafeMutablePointerToElements { elements in
            elements.advanced(by: index).moveInitialize(from: elements.advanced(by: sourceIndex), count: 1)
        }
    }

    @inlinable @inline(__always)
    func moveElement(at index: Int) -> Element {
//        precondition(index < pageCapacity)
        return withUnsafeMutablePointerToElements { buffer in
            buffer.advanced(by: index).move()
        }
    }

    @inlinable @inline(__always)
    func value(at index: Int) -> Element {
//        precondition(index < pageCapacity)
        return withUnsafeMutablePointerToElements { buffer in
            buffer[index]
        }
    }

    @inlinable @inline(__always)
    subscript(index: Int) -> Element {
        @inlinable @inline(__always)
        _read {
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

    @usableFromInline @inline(__always)
    func nextCapacity(current: Int, needed: Int) -> Int {
        var cap = max(current, 0)
        if cap >= needed { return cap }
        if cap == 0 { cap = max(1024, needed) }
        while cap < needed { cap &+= max(cap >> 1, 16) } // ~1.5× growth
        return cap
    }

    @inlinable @inline(__always) @discardableResult
    public func append(_ element: Element, storage: inout ContiguousStorage<Element>) -> Int {
        precondition(self === storage.buffer)

        var buffer = self
        let nextIndex = storage.count

        if nextIndex >= storage.capacity {
            buffer = buffer.ensureCapacity(
                forIndex: nextIndex,
                storage: &storage
            )
        }

        precondition(nextIndex < storage.capacity)

        buffer.withUnsafeMutablePointerToElements { elements in
            elements.advanced(by: nextIndex).initialize(to: element)
        }

        storage.count = nextIndex + 1
        return nextIndex
    }

    @inlinable @inline(__always)
    func get(_ index: Int, count: Int) -> Element {
        precondition(index < count)
        return withUnsafeMutablePointerToElements { elements in
            elements[index]
        }
    }

    @inlinable @inline(__always)
    public func getPointer(_ index: Int, count: Int) -> UnsafeMutablePointer<Element> {
        precondition(index < count)
        return withUnsafeMutablePointerToElements { elements in
            elements.advanced(by: index)
        }
    }

    @inlinable @inline(__always)
    @discardableResult
    func remove(at index: Int, storage: inout ContiguousStorage<Element>) -> Element {
        precondition(self === storage.buffer)
        precondition(index < storage.count)

        let lastIndex = storage.count - 1

        let removed = moveElement(at: index)

        if index != lastIndex {
            moveInitializeElement(at: index, sourceIndex: lastIndex)
        }

        storage.count = lastIndex

        return removed
    }

    @inlinable @inline(__always)
    func ensureCapacity(forIndex requiredIndex: Int, storage: inout ContiguousStorage<Element>) -> ContiguousBuffer {
        if requiredIndex < storage.capacity {
            return self
        }

        let newCapacity = nextCapacity(current: storage.capacity, needed: requiredIndex + 1)
        let newBuffer = ContiguousBuffer.create(initialCapacity: newCapacity)
        withUnsafeMutablePointerToElements { source in
            newBuffer.withUnsafeMutablePointerToElements { destination in
                destination.moveInitialize(from: source, count: storage.count)
            }
        }
        storage.buffer = newBuffer
        storage.capacity = newCapacity
        return newBuffer
    }
}
