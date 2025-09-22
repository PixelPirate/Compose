import BitCollections
import Atomics

public protocol Component: ComponentResolving {
    @inlinable @inline(__always)
    static var componentTag: ComponentTag { get }

    @inlinable @inline(__always)
    static var requiresStorage: Bool { get }
}

public extension Component {
    @inlinable @inline(__always)
    static var requiresStorage: Bool { true }
}

public struct ComponentSignature: Hashable {
    @usableFromInline
    var rawHashValue: BitSet2

    @usableFromInline @inline(__always)
    internal init(raw: BitSet2) {
        rawHashValue = raw
    }

    @inlinable @inline(__always)
    public init(_ tags: ComponentTag...) {
        var bits = BitSet2()
        bits.insert(tags.map(\.rawValue))
        rawHashValue = bits
    }

    @inlinable @inline(__always)
    public mutating func append(_ tag: ComponentTag) {
        rawHashValue.insert(tag.rawValue)
    }

    @inlinable @inline(__always)
    public func appending(_ tag: ComponentTag) -> Self {
        var newSignature = rawHashValue
        newSignature.insert(tag.rawValue)
        return ComponentSignature(raw: newSignature)
    }

    @inlinable @inline(__always)
    public mutating func remove(_ tag: ComponentTag) {
        rawHashValue.remove(tag.rawValue)
    }

    @inlinable @inline(__always)
    public func removing(_ tag: ComponentTag) -> Self {
        var newSignature = rawHashValue
        newSignature.remove(tag.rawValue)
        return ComponentSignature(raw: newSignature)
    }
}

public struct ComponentTag: Hashable, Sendable {
    @inline(__always)
    public let rawValue: Int

    nonisolated(unsafe) private static var nextTag: UnsafeAtomic<Int> = .create(0)

    public static func makeTag() -> Self {
        ComponentTag(
            rawValue: Self.nextTag.loadThenWrappingIncrement(ordering: .sequentiallyConsistent)
        )
    }
}
