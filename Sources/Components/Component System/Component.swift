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

    @inlinable @inline(__always)
    static func makeResolvedDense(access: TypedAccess<Self>, denseIndex: Int, entityID: Entity.ID) -> ResolvedType

    @inlinable @inline(__always)
    static func makeReadOnlyResolvedDense(access: TypedAccess<Self>, denseIndex: Int, entityID: Entity.ID) -> ReadOnlyResolvedType
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

    @inlinable @inline(__always)
    static func makeResolvedDense(access: TypedAccess<QueriedComponent>, denseIndex: Int, entityID: Entity.ID) -> Self {
        access[dense: denseIndex]
    }

    @inlinable @inline(__always)
    static func makeReadOnlyResolvedDense(access: TypedAccess<QueriedComponent>, denseIndex: Int, entityID: Entity.ID) -> Self {
        access[dense: denseIndex]
    }
}

public struct QuerySignature: Hashable, Sendable {
    @usableFromInline
    let write: ComponentSignature
    @usableFromInline
    let readOnly: ComponentSignature
    @usableFromInline
    let backstage: ComponentSignature
    @usableFromInline
    let excluded: ComponentSignature

    @inlinable
    public init(write: ComponentSignature, readOnly: ComponentSignature, backstage: ComponentSignature, excluded: ComponentSignature) {
        self.write = write
        self.readOnly = readOnly
        self.backstage = backstage
        self.excluded = excluded
    }
}

// TODO: I think I can make a single signature will owned, non-owned and excluded components, and just check if a querys full signature is a superset of that. this should be correct.
// Correction 1: I need to separate the owned components.
//               E.g.: G1: Transform; Without<Gravity>   G2: Gravity; Without<Person>
//               Query: Gravity, With<Person>, Without<Transform>
//               Here both G1 and G2 would be a subset, but none of the two has the required entities in their dense prefix.
//
//               E.g.: G1: Transform, With<Gravity>   G2: Gravity, Person
//               Query: Transform; Gravity, Person
//               Here both G1 and G2 would be valid subsets, but only G2 would be the better dense prefix
public struct GroupSignature: Hashable, Sendable {
    /// An entity is part of this group if it contains all these
    @usableFromInline
    let contained: ComponentSignature
    @usableFromInline
    let excluded: ComponentSignature

    @inlinable
    public init(contained: ComponentSignature, excluded: ComponentSignature) {
        self.contained = contained
        self.excluded = excluded
    }

    @inlinable
    public init(_ querySignature: QuerySignature) {
        contained = querySignature.write.union(querySignature.readOnly).union(querySignature.backstage)
        excluded = querySignature.excluded
    }
}

@usableFromInline
struct GroupMetadata {
    @usableFromInline let owned: ComponentSignature
    @usableFromInline let backstage: ComponentSignature
    @usableFromInline let excluded: ComponentSignature
    @usableFromInline let contained: ComponentSignature

    @usableFromInline
    init(owned: ComponentSignature, backstage: ComponentSignature, excluded: ComponentSignature) {
        self.owned = owned
        self.backstage = backstage
        self.excluded = excluded
        self.contained = owned.union(backstage)
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
    public func isSubset(of other: ComponentSignature) -> Bool {
        rawHashValue.isSubset(of: other.rawHashValue)
    }

    @inlinable @inline(__always)
    public static func + (lhs: ComponentSignature, rhs: ComponentSignature) -> ComponentSignature {
        lhs.appending(rhs)
    }

    public var debugDescription: String {
        "ComponentSignature(bitCount: \(rawHashValue.bitCount), words: \(rawHashValue.words)"
    }

    @usableFromInline
    var tags: AnyIterator<ComponentTag> {
        let numberIterator = rawHashValue.numbers
        return AnyIterator {
            numberIterator.next().map(ComponentTag.init(rawValue:))
        }
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
