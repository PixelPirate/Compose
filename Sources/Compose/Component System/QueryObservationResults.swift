/// A sequence over a snapshot of observation storage that yields resolved query
/// tuples. The snapshot is captured at `observe(_:)` time via copy-on-write so
/// that iteration is safe even if the backing storage is mutated by a subsequent
/// observation-system run.
///
/// Follows the `AnyIterator` pattern used by `LazyQuerySequence`.
public struct QueryObservationResults<each T: ComponentResolving>: Sequence {
    public typealias Element = (repeat (each T).ReadOnlyResolvedType)

    @usableFromInline
    let elements: ContiguousArray<Element>

    @usableFromInline
    let _storageVersion: UInt64

    @inlinable @inline(__always)
    init(elements: ContiguousArray<Element>, storageVersion: UInt64) {
        self.elements = elements
        self._storageVersion = storageVersion
    }

    @inlinable @inline(__always)
    public var count: Int { elements.count }

    @inlinable @inline(__always)
    public var isEmpty: Bool { elements.isEmpty }

    @inlinable @inline(__always)
    public var storageVersion: UInt64 {
        _storageVersion
    }

    @inlinable @inline(__always)
    public func makeIterator() -> AnyIterator<Element> {
        var index = 0
        let elements = self.elements
        return AnyIterator {
            guard index < elements.count else { return nil }
            let value = elements[index]
            index &+= 1
            return value
        }
    }
}