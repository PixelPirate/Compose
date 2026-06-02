/// A sequence over observation storage that yields resolved query tuples.
/// Follows the exact `AnyIterator` pattern used by `LazyQuerySequence`.
public struct QueryObservationResults<each T: ComponentResolving>: Sequence {
    public typealias Element = (repeat (each T).ReadOnlyResolvedType)

    @usableFromInline
    let storage: QueryObservationStorage<repeat each T>

    @inlinable @inline(__always)
    init(storage: QueryObservationStorage<repeat each T>) {
        self.storage = storage
    }

    @inlinable @inline(__always)
    public var count: Int { storage.count }

    @inlinable @inline(__always)
    public var isEmpty: Bool { storage.isEmpty }

    @inlinable @inline(__always)
    public var storageVersion: UInt64 {
        storage.storageVersion
    }

    @inlinable @inline(__always)
    public func makeIterator() -> AnyIterator<Element> {
        let elements = storage.elements
        var index = 0
        return AnyIterator {
            guard index < elements.count else { return nil }
            let value = elements[index]
            index &+= 1
            return value
        }
    }
}