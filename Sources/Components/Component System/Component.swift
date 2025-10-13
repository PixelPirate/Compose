import Atomics

public protocol Component: ComponentResolving, SendableMetatype {
    @inlinable @inline(__always)
    static var componentTag: ComponentTag { get }

    @inlinable @inline(__always)
    static var storage: ComponentStorage { get }
}

public enum ComponentStorage {
    case sparseSet
}

public extension Component {
    @inlinable @inline(__always)
    static var storage: ComponentStorage { .sparseSet }
}

public protocol ComponentResolving {
    associatedtype ResolvedType = Self
    associatedtype ReadOnlyResolvedType = Self
    associatedtype QueriedComponent: Component = Self

    @inlinable @inline(__always)
    static func makeResolved(access: TypedAccess<Self>, entityID: Entity.ID) -> ResolvedType

    @inlinable @inline(__always)
    static func makeReadOnlyResolved(access: TypedAccess<Self>, entityID: Entity.ID) -> ReadOnlyResolvedType
}

public extension ComponentResolving where Self: Component, ResolvedType == Self, QueriedComponent == Self, ReadOnlyResolvedType == Self {
    @inlinable @inline(__always)
    static func makeResolved(access: TypedAccess<QueriedComponent>, entityID: Entity.ID) -> Self {
        access[entityID]
    }

    @inlinable @inline(__always)
    static func makeReadOnlyResolved(access: TypedAccess<QueriedComponent>, entityID: Entity.ID) -> Self {
        access[entityID]
    }
}

public struct ComponentSignature: Hashable, Sendable, CustomDebugStringConvertible {
    @usableFromInline
    var rawHashValue: BitSet

    @usableFromInline @inline(__always)
    internal var isEmpty: Bool {
        _read {
            yield rawHashValue.bitCount == 0
        }
    }

    @usableFromInline @inline(__always)
    internal init(raw: BitSet) {
        rawHashValue = raw
    }

    @inlinable @inline(__always)
    public init(_ tags: ComponentTag...) {
        var bits = BitSet()
        bits.insert(tags.map(\.rawValue))
        rawHashValue = bits
    }

    @inlinable @inline(__always)
    public init(_ tags: some Sequence<ComponentTag>) {
        var bits = BitSet()
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
    public func appending(_ signature: ComponentSignature) -> Self {
        ComponentSignature(raw: rawHashValue.union(signature.rawHashValue))
    }

    @inlinable @inline(__always)
    public mutating func remove(_ tag: ComponentTag) {
        rawHashValue.remove(tag.rawValue)
    }

    @inlinable @inline(__always)
    public mutating func remove(_ signature: ComponentSignature) {
        rawHashValue.subtract(signature.rawHashValue)
    }

    @inlinable @inline(__always)
    public func contains(_ tag: ComponentTag) -> Bool {
        rawHashValue.contains(tag.rawValue)
    }

    @inlinable @inline(__always)
    public func removing(_ tag: ComponentTag) -> Self {
        var newSignature = rawHashValue
        newSignature.remove(tag.rawValue)
        return ComponentSignature(raw: newSignature)
    }

    @inlinable @inline(__always)
    public func union(_ other: ComponentSignature) -> Self {
        appending(other)
    }

    @inlinable @inline(__always)
    public mutating func formUnion(_ other: ComponentSignature) {
        rawHashValue.formUnion(other.rawHashValue)
    }

    @inlinable @inline(__always)
    public func isDisjoint(with other: ComponentSignature) -> Bool {
        rawHashValue.isDisjoint(with: other.rawHashValue)
    }

    @inlinable @inline(__always)
    public static func + (lhs: ComponentSignature, rhs: ComponentSignature) -> ComponentSignature {
        lhs.appending(rhs)
    }

    public var debugDescription: String {
        "ComponentSignature(bitCount: \(rawHashValue.bitCount), words: \(rawHashValue.words)"
    }
}

public struct ComponentTag: Hashable, Sendable {
    @inline(__always)
    public let rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    nonisolated(unsafe) private static var nextTag: UnsafeAtomic<Int> = .create(0)

    public static func makeTag() -> Self {
        ComponentTag(
            rawValue: Self.nextTag.loadThenWrappingIncrement(ordering: .sequentiallyConsistent)
        )
    }
}
