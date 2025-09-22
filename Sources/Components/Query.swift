import Foundation
import BitCollections

public struct QueryHash: Hashable {
    let value: Int

    public init<each T: Component>(_ query: Query<repeat each T>) {
        var inc = BitSet()
        for type in repeat (each T).self {
            if type.requiresStorage {
                inc.insert(type.componentTag.rawValue)
            }
        }

        var bac = BitSet()
        for tag in query.backstageComponents {
            bac.insert(tag.rawValue)
        }

        var exc = BitSet()
        for tag in query.excludedComponents {
            exc.insert(tag.rawValue)
        }

        var hasher = Hasher()
        hasher.combine(inc)
        hasher.combine(bac)
        hasher.combine(exc)
        self.value = hasher.finalize()
    }
}

@usableFromInline
struct QueryPlan {
    @usableFromInline
    let base: ContiguousArray<SlotIndex>
    @usableFromInline
    let others: [ContiguousArray<Array.Index>] // entityToComponents maps
    @usableFromInline
    let excluded: [ContiguousArray<Array.Index>]
    @usableFromInline
    let version: UInt64

    @usableFromInline
    init(base: ContiguousArray<SlotIndex>, others: [ContiguousArray<Array.Index>], excluded: [ContiguousArray<Array.Index>], version: UInt64) {
        self.base = base
        self.others = others
        self.excluded = excluded
        self.version = version
    }
}
extension TypedAccess {
    static var empty: TypedAccess {
        // a harmless instance that never resolves anything
        TypedAccess(
            buffer: UnsafeMutableBufferPointer(start: nil, count: 0),
            indices: []
        )
    }
}

public struct LazyQuerySequence<each T: Component>: Sequence {
    private let entityIDs: [Entity.ID]
    private let accessors: (repeat TypedAccess<(each T).QueriedComponent>)

    init(entityIDs: [Entity.ID], accessors: repeat TypedAccess<(each T).QueriedComponent>) {
        self.entityIDs = entityIDs
        self.accessors = (repeat each accessors)
    }

    init() {
        self.entityIDs = []
        self.accessors = (repeat TypedAccess<(each T).QueriedComponent>.empty)
    }

    public func makeIterator() -> AnyIterator<(repeat (each T).ReadOnlyResolvedType)> {
        var index = 0
        return AnyIterator {
            guard index < entityIDs.count else { return nil }
            let id = entityIDs[index]
            index += 1
            return (repeat (each T).makeReadOnlyResolved(access: each accessors, entityID: id))
        }
    }
}

public struct Query<each T: Component> where repeat each T: ComponentResolving {
    /// These components will be used for selecting the correct archetype, but they will not be included in the query output.
    public let backstageComponents: Set<ComponentTag> // Or witnessComponents?

    public let excludedComponents: Set<ComponentTag>

    public let includeEntityID: Bool

    public func appending<U>(_ type: U.Type = U.self) -> Query<repeat each T, U> {
        Query<repeat each T, U>(
            backstageComponents: backstageComponents,
            excludedComponents: excludedComponents,
            includeEntityID: includeEntityID
        )
    }

    @usableFromInline @inline(__always)
    internal func getArrays(_ coordinator: inout Coordinator) -> (base: ContiguousArray<SlotIndex>, others: [ContiguousArray<Int>], excluded: [ContiguousArray<Int>])? {
        let hash = QueryHash(self)
        if
            let cached = coordinator.queryCache[hash],
            cached.version == coordinator.worldVersion
        {
            return (
                cached.base,
                cached.others,
                cached.excluded
            )
        } else {
            guard let new = coordinator.pool.baseAndOthers(
                repeat (each T).QueriedComponent.self,
                included: backstageComponents,
                excluded: excludedComponents
            ) else {
                return nil
            }
            coordinator.queryCache[hash] = QueryPlan(
                base: new.base,
                others: new.others,
                excluded: new.excluded,
                version: coordinator.worldVersion
            )
            return new
        }
    }

    @inlinable @inline(__always)
    public func perform(_ coordinator: inout Coordinator, _ handler: (repeat (each T).ResolvedType) -> Void) {
        guard let (baseIndices, otherIndexMaps, excludedMaps) = getArrays(&coordinator) else { return }

        withTypedBuffers(&coordinator.pool) { (
            buffers: repeat (UnsafeMutableBufferPointer<(each T).QueriedComponent>, ContiguousArray<ContiguousArray.Index>)
        ) in
            let accessors = (repeat TypedAccess(buffer: (each buffers).0, indices: (each buffers).1))
            slotLoop: for slot in baseIndices {
                let slotRaw = slot.rawValue
                for map in otherIndexMaps where !map.indices.contains(slotRaw) || map[slotRaw] == .notFound {
                    // Entity does not have all required components, skip.
                    continue slotLoop
                }
                for map in excludedMaps where map.indices.contains(slotRaw) && map[slotRaw] != .notFound {
                    // Entity has at least one excluded component, skip.
                    continue slotLoop
                }
                let id = Entity.ID(slot: SlotIndex(rawValue: slotRaw))
                handler(repeat (each T).makeResolved(access: each accessors, entityID: id))
            }
        }
    }

    @inlinable @inline(__always)
    public func performParallel(_ coordinator: inout Coordinator, _ handler: (repeat (each T).ResolvedType) -> Void) {
        let entityIDs = coordinator.pool.entities(repeat (each T).QueriedComponent.self, included: backstageComponents, excluded: excludedComponents)

        withTypedBuffers(&coordinator.pool) { (
            buffers: repeat (UnsafeMutableBufferPointer<(each T).QueriedComponent>, ContiguousArray<ContiguousArray.Index>)
        ) in
            let accessors = (repeat TypedAccess(buffer: (each buffers).0, indices: (each buffers).1))
            let cores = ProcessInfo.processInfo.processorCount
            let chunkSize = (entityIDs.count + cores - 1) / cores

            DispatchQueue.concurrentPerform(iterations: min(cores, entityIDs.count)) { i in
                let start = i * chunkSize
                let end = min(start + chunkSize, entityIDs.count)

                for entityId in entityIDs[start..<end] {
                    handler(repeat (each T).makeResolved(access: each accessors, entityID: entityId))
                }
            }
        }
    }

    public func fetchAll(_ coordinator: inout Coordinator) -> LazyQuerySequence<repeat each T> {
        let entityIDs = coordinator.pool.entities(
            repeat (each T).QueriedComponent.self,
            included: backstageComponents,
            excluded: excludedComponents
        )

        let accessors = withTypedBuffers(&coordinator.pool) { (
            buffers: repeat (UnsafeMutableBufferPointer<(each T).QueriedComponent>,
                             ContiguousArray<ContiguousArray.Index>)
        ) in
            (repeat TypedAccess(buffer: (each buffers).0, indices: (each buffers).1))
        }

        guard let accessors else {
            return LazyQuerySequence()
        }

        return LazyQuerySequence(entityIDs: entityIDs, accessors: repeat each accessors)
    }

    public func fetchOne(_ coordinator: inout Coordinator) -> (repeat (each T).ReadOnlyResolvedType)? {
        var result: (repeat (each T).ReadOnlyResolvedType)? = nil
        let entityIDs = coordinator.pool.entities(
            repeat (each T).QueriedComponent.self,
            included: backstageComponents,
            excluded: excludedComponents
        )
        withTypedBuffers(&coordinator.pool) { (
            buffers: repeat (UnsafeMutableBufferPointer<(each T).QueriedComponent>, ContiguousArray<ContiguousArray.Index>)
        ) in
            let accessors = (repeat TypedAccess(buffer: (each buffers).0, indices: (each buffers).1))
            for entityId in entityIDs {
                result = (repeat (each T).makeReadOnlyResolved(access: each accessors, entityID: entityId))
                break
            }
        }

        return result
    }

    public func callAsFunction(_ coordinator: inout Coordinator, _ handler: (repeat (each T).ResolvedType) -> Void) {
        perform(&coordinator, handler)
    }

    public var signature: ComponentSignature {
        var signature = ComponentSignature()

        for tag in backstageComponents {
            signature = signature.appending(tag)
        }

        func add(_ tag: ComponentTag) {
            signature = signature.appending(tag)
        }

        for tagType in repeat (each T).self {
            guard tagType.requiresStorage else { continue }
            signature = signature.appending(tagType.componentTag)
        }

        return signature
    }
}

public struct TypedAccess<C: Component>: @unchecked Sendable {
    /*@usableFromInline*/ public var buffer: UnsafeMutableBufferPointer<C>
    /*@usableFromInline*/ public var indices: ContiguousArray<ContiguousArray.Index>

    @usableFromInline
    init(buffer: UnsafeMutableBufferPointer<C>, indices: ContiguousArray<ContiguousArray.Index>) {
        self.buffer = buffer
        self.indices = indices
    }

    @inlinable @inline(__always)
    public subscript(_ id: Entity.ID) -> C {
        _read {
            yield buffer[indices[id.slot.rawValue]]
        }
        nonmutating _modify {
            yield &buffer[indices[id.slot.rawValue]]
        }
    }

    @inlinable @inline(__always)
    public func access(_ id: Entity.ID) -> SingleTypedAccess<C> {
        SingleTypedAccess(buffer: buffer.baseAddress!.advanced(by: indices[id.slot.rawValue]))
    }
}

public struct SingleTypedAccess<C: Component> {
    @usableFromInline internal var buffer: UnsafeMutablePointer<C>

    @usableFromInline
    init(buffer: UnsafeMutablePointer<C>) {
        self.buffer = buffer
    }

    @inlinable @inline(__always)
    public var value: C {
        _read {
            yield buffer.pointee
        }
        nonmutating _modify {
            yield &buffer.pointee
        }
    }
}

public protocol ComponentResolving {
    associatedtype ResolvedType = Self
    associatedtype ReadOnlyResolvedType = Self
    associatedtype QueriedComponent: Component = Self

    @inlinable @inline(__always)
    static func makeResolved(access: TypedAccess<QueriedComponent>, entityID: Entity.ID) -> ResolvedType

    @inlinable @inline(__always)
    static func makeReadOnlyResolved(access: TypedAccess<QueriedComponent>, entityID: Entity.ID) -> ReadOnlyResolvedType
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

extension Write: ComponentResolving {
    public typealias ResolvedType = Write<Wrapped>
    public typealias ReadOnlyResolvedType = Wrapped
    public typealias QueriedComponent = Wrapped

    @inlinable @inline(__always)
    public static func makeResolved(access: TypedAccess<Wrapped>, entityID: Entity.ID) -> Write<Wrapped> {
        Write<Wrapped>(access: access.access(entityID))
    }

    @inlinable @inline(__always)
    public static func makeReadOnlyResolved(access: TypedAccess<Wrapped>, entityID: Entity.ID) -> Wrapped {
        access[entityID]
    }
}

public struct BuiltQuery<each T: Component & ComponentResolving> {
    let composite: Query<repeat each T>
}

@resultBuilder
public enum QueryBuilder {
    public static func buildExpression<C: Component>(_ c: C.Type) -> BuiltQuery<C> {
        BuiltQuery(
            composite: Query<C>(
                backstageComponents: [],
                excludedComponents: [],
                includeEntityID: false
            )
        )
    }

    public static func buildExpression<C: Component>(_ c: Write<C>.Type) -> BuiltQuery<Write<C>> {
        BuiltQuery(
            composite: Query<Write<C>>(
                backstageComponents: [],
                excludedComponents: [],
                includeEntityID: false
            )
        )
    }

    public static func buildExpression<C: Component>(_ c: With<C>.Type) -> BuiltQuery< > {
        BuiltQuery(
            composite: Query< >(
                backstageComponents: [C.componentTag],
                excludedComponents: [],
                includeEntityID: false
            )
        )
    }

    public static func buildExpression<C: Component>(_ c: Without<C>.Type) -> BuiltQuery< > {
        BuiltQuery(
            composite: Query< >(
                backstageComponents: [],
                excludedComponents: [C.componentTag],
                includeEntityID: false
            )
        )
    }

    public static func buildExpression(_ c: WithEntityID) -> BuiltQuery<WithEntityID> {
        BuiltQuery(
            composite: Query<WithEntityID>(
                backstageComponents: [],
                excludedComponents: [],
                includeEntityID: true
            )
        )
    }

    public static func buildPartialBlock<each T>(first: BuiltQuery<repeat each T>) -> BuiltQuery<repeat each T> {
        first
    }

    public static func buildPartialBlock<each T, each U>(
        accumulated: BuiltQuery<repeat each T>,
        next: BuiltQuery<repeat each U>
    ) -> BuiltQuery<repeat each T, repeat each U> {
        BuiltQuery(
            composite:
                Query<repeat each T,repeat each U>(
                    backstageComponents:
                        accumulated.composite.backstageComponents.union(next.composite.backstageComponents),
                    excludedComponents:
                        accumulated.composite.excludedComponents.union(next.composite.excludedComponents),
                    includeEntityID:
                        accumulated.composite.includeEntityID || next.composite.includeEntityID
                )
        )
    }
}

public extension Query {
    init(@QueryBuilder _ content: () -> BuiltQuery<repeat each T>) {
        let built = content()
        self = built.composite
    }
}

protocol WritableComponent: Component {
    associatedtype Wrapped: Component
}

@dynamicMemberLookup
public struct Write<C: Component>: WritableComponent {
    public static var componentTag: ComponentTag { C.componentTag }

    public typealias Wrapped = C

    @usableFromInline
    let access: SingleTypedAccess<C>

    @usableFromInline
    init(access: SingleTypedAccess<C>) {
        self.access = access
    }

    @inlinable @inline(__always)
    public subscript<R>(dynamicMember keyPath: WritableKeyPath<C, R>) -> R {
        _read {
            yield access.value[keyPath: keyPath]
        }
        nonmutating _modify {
            yield &access.value[keyPath: keyPath]
        }
    }
}

public struct With<C: Component>: Component {
    public static var componentTag: ComponentTag { C.componentTag }

    public typealias Wrapped = C
}

public struct WithEntityID: Component {
    public static var componentTag: ComponentTag { ComponentTag(rawValue: -1) }
    public typealias ResolvedType = Entity.ID
    public typealias ReadOnlyResolvedType = Entity.ID

    public static var requiresStorage: Bool { false }

    public init() {}

    @inlinable @inline(__always)
    public static func makeResolved(access: TypedAccess<QueriedComponent>, entityID: Entity.ID) -> ResolvedType {
        entityID
    }

    @inlinable @inline(__always)
    public static func makeReadOnlyResolved(access: TypedAccess<QueriedComponent>, entityID: Entity.ID) -> ResolvedType {
        entityID
    }
}

public struct Without<C: Component>: Component {
    public static var componentTag: ComponentTag { C.componentTag }
}

@discardableResult
@usableFromInline
func withTypedBuffers<each C: Component, R>(
    _ pool: inout ComponentPool,
    _ body: (repeat (UnsafeMutableBufferPointer<each C>, ContiguousArray<ContiguousArray.Index>)) throws -> R
) rethrows -> R? {
    var tuple: (repeat (UnsafeMutableBufferPointer<each C>, ContiguousArray<ContiguousArray.Index>))? = nil

    func buildTuple() -> (repeat (UnsafeMutableBufferPointer<each C>, ContiguousArray<ContiguousArray.Index>))? {
        return (repeat tryGetBuffer((each C).self)!)
    }

    func tryGetBuffer<D: Component>(_ type: D.Type) -> (UnsafeMutableBufferPointer<D>, ContiguousArray<ContiguousArray.Index>)? {
        if !D.requiresStorage {
            // TODO: Returning this is quite ugly, can I prevent this case?
            return (UnsafeMutableBufferPointer(start: UnsafeMutablePointer(nil), count: 0), ContiguousArray())
        }
        guard let anyArray = pool.components[D.componentTag] else { return nil }
        var result: (UnsafeMutableBufferPointer<D>, ContiguousArray<ContiguousArray.Index>)? = nil
        anyArray.withBuffer(D.self) { buffer, entitiesToIndices in
            result = (buffer, entitiesToIndices)
        }
        return result
    }

    guard let built = buildTuple() else { return nil }
    tuple = built
    return try body(repeat each tuple!)
}
