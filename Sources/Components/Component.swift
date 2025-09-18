import BitCollections
import Atomics

public protocol Component: ComponentResolving {
    static var componentTag: ComponentTag { get }
}

public struct ComponentSignature: Hashable {
    var rawHashValue: BitSet

    private init(raw: BitSet) {
        rawHashValue = raw
    }

    public init(_ tags: ComponentTag...) {
        rawHashValue = tags.reduce(into: BitSet()) { bitSet, tag in
            bitSet.insert(tag.rawValue)
        }
    }

    public mutating func append(_ tag: ComponentTag) {
        rawHashValue.insert(tag.rawValue)
    }

    public func appending(_ tag: ComponentTag) -> Self {
        var newSignature = rawHashValue
        newSignature.insert(tag.rawValue)
        return ComponentSignature(raw: newSignature)
    }

    public mutating func remove(_ tag: ComponentTag) {
        rawHashValue.remove(tag.rawValue)
    }

    public func removing(_ tag: ComponentTag) -> Self {
        var newSignature = rawHashValue
        newSignature.remove(tag.rawValue)
        return ComponentSignature(raw: newSignature)
    }
}

public struct ComponentTag: Hashable, Sendable {
    public let rawValue: Int

    nonisolated(unsafe) private static var nextTag: UnsafeAtomic<Int> = .create(0)

    public static func makeTag() -> Self {
        ComponentTag(
            rawValue: Self.nextTag.loadThenWrappingIncrement(ordering: .sequentiallyConsistent)
        )
    }
}
