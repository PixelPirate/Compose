import Foundation
import BitCollections

public struct QueryHash: Hashable {
    let value: Int

    public init<each T: Component>(_ query: Query<repeat each T>) {
        var inc = BitSet()
        for tag in repeat (each T).componentTag {
            inc.insert(tag.rawValue)
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
    private let accessors: (repeat TypedAccess<(each T).InnerType>)

    init(entityIDs: [Entity.ID], accessors: repeat TypedAccess<(each T).InnerType>) {
        self.entityIDs = entityIDs
        self.accessors = (repeat each accessors)
    }

    init() {
        self.entityIDs = []
    }

    public func makeIterator() -> AnyIterator<(Entity.ID, repeat (each T).InnerType)> {
        var index = 0
        return AnyIterator {
            guard index < entityIDs.count else { return nil }
            let id = entityIDs[index]
            index += 1
            let tuple = (repeat (each accessors).access(id).value)
            return (id, tuple)
        }
    }
}

public struct Query<each T: Component> where repeat each T: ComponentResolving {
    /// These components will be used for selecting the correct archetype, but they will not be included in the query output.
    public let backstageComponents: Set<ComponentTag> // Or witnessComponents?

    public let excludedComponents: Set<ComponentTag>

    public func appending<U>(_ type: U.Type = U.self) -> Query<repeat each T, U> {
        Query<repeat each T, U>(backstageComponents: backstageComponents, excludedComponents: excludedComponents)
    }

    @inlinable @inline(__always)
    public func perform(_ coordinator: inout Coordinator, _ handler: (repeat (each T).ResolvedType) -> Void) {
        @inline(__always)
        func getLists() -> (base: ContiguousArray<SlotIndex>, others: [ContiguousArray<Int>], excluded: [ContiguousArray<Int>])? {
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
                    repeat (each T).InnerType.self,
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

        guard let (baseIndices, otherIndexMaps, excludedMaps) = getLists() else { return }

        withTypedBuffers(&coordinator.pool) { (
            buffers: repeat (UnsafeMutableBufferPointer<(each T).InnerType>, ContiguousArray<ContiguousArray.Index>)
        ) in
            let accessors = (repeat TypedAccess(buffer: (each buffers).0, indices: (each buffers).1))
            slotLoop: for slot in baseIndices {
                let slotRaw = slot.rawValue
                for map in otherIndexMaps where map.indices.contains(slotRaw) && map[slotRaw] == .notFound {
                    // Entity does not have all required components, skip.
                    continue slotLoop
                }
                for map in excludedMaps where map.indices.contains(slotRaw) && map[slotRaw] != .notFound {
                    // Entity has at least one excluded component, skip.
                    continue slotLoop
                }
                let id = Entity.ID(slot: SlotIndex(rawValue: slotRaw))
                handler(repeat (each T).makeResolved(access: each accessors, entityID: id))

//     This does work, but it only makes sense when the workload is massive. How could I detect that beforehand?
//     In Bevy, the systems need to opt in: https://docs.rs/bevy/latest/bevy/prelude/struct.Query.html#method.par_iter
//     https://bevy-cheatbook.github.io/programming/par-iter.html
//                let cores = ProcessInfo.processInfo.processorCount
//                let chunkSize = (entityIDs.count + cores - 1) / cores
//
//                DispatchQueue.concurrentPerform(iterations: cores) { i in
//                    let start = i * chunkSize
//                    let end = min(start + chunkSize, entityIDs.count)
//
//                    for entityId in entityIDs[start..<end] {
//                        handler(repeat (each T).makeResolved(access: each accessors, entityID: entityId))
//                    }
//                }
            }
        }
    }

    public func fetchAll(_ coordinator: inout Coordinator) -> QueryIter<repeat each T> {
        let entityIDs = coordinator.pool.entities(
            repeat (each T).InnerType.self,
            included: backstageComponents,
            excluded: excludedComponents
        )

        let accessors = withTypedBuffers(&coordinator.pool) { (
            buffers: repeat (UnsafeMutableBufferPointer<(each T).InnerType>,
                             ContiguousArray<ContiguousArray.Index>)
        ) in
            (repeat TypedAccess(buffer: (each buffers).0, indices: (each buffers).1))
        }

        guard let accessors else {
            return QueryIter()
        }

        return LazyQuerySequence(entityIDs: entityIDs, accessors: repeat each accessors)
    }
//    public func fetchAll(_ coordinator: inout Coordinator) -> [Entity.ID: (repeat (each T).InnerType)] {
//        var result: [Entity.ID: (repeat (each T).InnerType)] = [:]
//        let entityIDs = coordinator.pool.entities(
//            repeat (each T).InnerType.self,
//            included: backstageComponents,
//            excluded: excludedComponents
//        )
//        withTypedBuffers(&coordinator.pool) { (
//            buffers: repeat (UnsafeMutableBufferPointer<(each T).InnerType>, ContiguousArray<ContiguousArray.Index>)
//        ) in
//            let accessors = (repeat TypedAccess(buffer: (each buffers).0, indices: (each buffers).1))
//            for entityId in entityIDs {
//                result[entityId] = (repeat (each accessors).access(entityId).value)
//            }
//        }
//
//        return result
//    }

    public func fetchOne(_ coordinator: inout Coordinator) -> (entityID: Entity.ID, components: (repeat (each T).InnerType))? {
        var result: (entityID: Entity.ID, components: (repeat (each T).InnerType))? = nil
        let entityIDs = coordinator.pool.entities(
            repeat (each T).InnerType.self,
            included: backstageComponents,
            excluded: excludedComponents
        )
        withTypedBuffers(&coordinator.pool) { (
            buffers: repeat (UnsafeMutableBufferPointer<(each T).InnerType>, ContiguousArray<ContiguousArray.Index>)
        ) in
            let accessors = (repeat TypedAccess(buffer: (each buffers).0, indices: (each buffers).1))
            for entityId in entityIDs {
                result = (entityID: entityId, (repeat (each accessors).access(entityId).value))
                break
            }
        }

        return result
    }

    // TODO: Make a version which returns the result (Most useful together with entity ID filters).
    //       Call it `fetchAll` and `fetchOne`.
    //       E.g.: let transform = coordinator.fetchOne(Query { Transform.self; Entities(4) })
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

        repeat signature = signature.appending((each T).componentTag)

        return signature
    }
}

public struct TypedAccess<C: Component> {
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
    associatedtype InnerType: Component = Self
    static func makeResolved(access: TypedAccess<InnerType>, entityID: Entity.ID) -> ResolvedType
}

public extension ComponentResolving where Self: Component, ResolvedType == Self, InnerType == Self {
    static func makeResolved(access: TypedAccess<InnerType>, entityID: Entity.ID) -> Self {
        access[entityID]
    }
}

extension Write: ComponentResolving {
    public typealias ResolvedType = Write<Wrapped>
    public typealias InnerType = Wrapped

    public static func makeResolved(access: TypedAccess<Wrapped>, entityID: Entity.ID) -> Write<Wrapped> {
        Write<Wrapped>(access: access.access(entityID))
    }
}

public struct BuiltQuery<each T: Component & ComponentResolving> {
    let composite: Query<repeat each T>
}

@resultBuilder
public enum QueryBuilder {
    public static func buildExpression<C: Component>(_ c: C.Type) -> BuiltQuery<C> {
        BuiltQuery(composite: Query<C>(backstageComponents: [], excludedComponents: []))
    }

    public static func buildExpression<C: Component>(_ c: Write<C>.Type) -> BuiltQuery<Write<C>> {
        BuiltQuery(composite: Query<Write<C>>(backstageComponents: [], excludedComponents: []))
    }

    public static func buildExpression<C: Component>(_ c: With<C>.Type) -> BuiltQuery< > {
        BuiltQuery(composite: Query< >(backstageComponents: [C.componentTag], excludedComponents: []))
    }

    public static func buildExpression<C: Component>(_ c: Without<C>.Type) -> BuiltQuery< > {
        BuiltQuery(composite: Query< >(backstageComponents: [], excludedComponents: [C.componentTag]))
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
