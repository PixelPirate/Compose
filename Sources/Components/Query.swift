import Foundation

public struct QueryHash: Hashable {
    let value: Int

    public init<each T: Component>(_ query: Query<repeat each T>) {
        var hasher = Hasher()
        hasher.combine(query.signature)
        hasher.combine(query.excludedSignature)
        self.value = hasher.finalize()
    }
}

@usableFromInline
struct QueryPlan {
    @usableFromInline
    let base: ContiguousArray<SlotIndex>
//    @usableFromInline
//    let others: [ContiguousArray<Array.Index>] // entityToComponents maps
//    @usableFromInline
//    let excluded: [ContiguousArray<Array.Index>]
    @usableFromInline
    let version: UInt64

    @usableFromInline
    init(
        base: ContiguousArray<SlotIndex>,
//        others: [ContiguousArray<Array.Index>],
//        excluded: [ContiguousArray<Array.Index>],
        version: UInt64
    ) {
        self.base = base
//        self.others = others
//        self.excluded = excluded
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
    @inline(__always)
    public let backstageComponents: Set<ComponentTag> // Or witnessComponents?

    @inline(__always)
    public let excludedComponents: Set<ComponentTag>

    @inline(__always)
    public let includeEntityID: Bool

    @inline(__always)
    public let signature: ComponentSignature

    @inline(__always)
    public let excludedSignature: ComponentSignature

    @usableFromInline
    init(
        backstageComponents: Set<ComponentTag>,
        excludedComponents: Set<ComponentTag>,
        includeEntityID: Bool
    ) {
        self.backstageComponents = backstageComponents
        self.excludedComponents = excludedComponents
        self.includeEntityID = includeEntityID
        self.signature = Self.makeSignature(backstageComponents: backstageComponents)
        self.excludedSignature = Self.makeExcludedSignature(excludedComponents)
    }

    @inlinable @inline(__always)
    public func appending<U>(_ type: U.Type = U.self) -> Query<repeat each T, U> {
        Query<repeat each T, U>(
            backstageComponents: backstageComponents,
            excludedComponents: excludedComponents,
            includeEntityID: includeEntityID
        )
    }

    @usableFromInline @inline(__always)
    internal func getArrays(_ coordinator: inout Coordinator)
//    -> (base: ContiguousArray<SlotIndex>, others: [ContiguousArray<Int>], excluded: [ContiguousArray<Int>])?
    -> ContiguousArray<SlotIndex>?
    {
        let hash = QueryHash(self)
        if
            let cached = coordinator.queryCache[hash],
            cached.version == coordinator.worldVersion
        {
            return (
                cached.base
//                cached.others,
//                cached.excluded
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
                base: new,//.base,
//                others: new.others,
//                excluded: new.excluded,
                version: coordinator.worldVersion
            )
            return new
        }
    }

    @inlinable @inline(__always)
    public func perform(_ coordinator: inout Coordinator, _ handler: (repeat (each T).ResolvedType) -> Void) {
        guard let baseSlots = getArrays(&coordinator) else { return }

        withTypedBuffers(&coordinator.pool) { (
            accessors: repeat TypedAccess<(each T).QueriedComponent>
        ) in
            // 0.0137s
            let querySignature = self.signature
            let excludedSignature = self.excludedSignature

            slotLoop: for slot in baseSlots {
                let slotRaw = slot.rawValue
                let signature = coordinator.entitySignatures[slotRaw]

                guard
                    signature.rawHashValue.isSuperset(of: querySignature.rawHashValue),
                    signature.rawHashValue.isDisjoint(with: excludedSignature.rawHashValue)
                else {
                    continue slotLoop
                }

//                for component in otherComponents where !component.indices.contains(slotRaw) || component[slotRaw] == .notFound {
//                    // Entity does not have all required components, skip.
//                    continue slotLoop
//                }
//                for component in excludedComponents where component.indices.contains(slotRaw) && component[slotRaw] != .notFound {
//                    // Entity has at least one excluded component, skip.
//                    continue slotLoop
//                }
                let id = Entity.ID(slot: SlotIndex(rawValue: slotRaw))
                handler(repeat (each T).makeResolved(access: each accessors, entityID: id))
            }
        }
    }

    @inlinable @inline(__always)
    public func performParallel(_ coordinator: inout Coordinator, _ handler: (repeat (each T).ResolvedType) -> Void) {
        let entityIDs = coordinator.pool.entities(repeat (each T).QueriedComponent.self, included: backstageComponents, excluded: excludedComponents)

        withTypedBuffers(&coordinator.pool) { (
            accessors: repeat TypedAccess<(each T).QueriedComponent>
        ) in
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
            accessors: repeat TypedAccess<(each T).QueriedComponent>
        ) in
            (repeat each accessors)
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
            accessors: repeat TypedAccess<(each T).QueriedComponent>
        ) in
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

    @inlinable @inline(__always)
    static func makeSignature(backstageComponents: Set<ComponentTag>) -> ComponentSignature {
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

    @inlinable @inline(__always)
    static func makeExcludedSignature(_ excludedComponents: Set<ComponentTag>) -> ComponentSignature {
        var signature = ComponentSignature()

        for tag in excludedComponents {
            signature = signature.appending(tag)
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

    @inlinable @inline(__always)
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

    @inlinable @inline(__always)
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
    _ body: (repeat TypedAccess<each C>) throws -> R
) rethrows -> R? {
    var tuple: (repeat TypedAccess<each C>)? = nil

    func buildTuple() -> (repeat TypedAccess<each C>)? {
        return (repeat tryMakeAccess((each C).self)!)
    }

    func tryMakeAccess<D: Component>(_ type: D.Type) -> TypedAccess<D>? {
        if !D.requiresStorage {
            return TypedAccess<D>.empty
        }
        guard let anyArray = pool.components[D.componentTag] else { return nil }
        var result: TypedAccess<D>? = nil
        anyArray.withBuffer(D.self) { buffer, entitiesToIndices in
            result = TypedAccess(buffer: buffer, indices: entitiesToIndices)
            // Escaping the buffer here is bad, but we need a pack splitting in calls and recursive flatten in order to resolve this.
            // See: https://forums.swift.org/t/pitch-pack-destructuring-pack-splitting/79388/12
            // See: https://forums.swift.org/t/passing-a-parameter-pack-to-a-function-call-fails-to-compile/72243/15
        }
        return result
    }

    guard let built = buildTuple() else { return nil }
    tuple = built
    return try body(repeat each tuple!)


}

func entuplePack<each Prefix, Last>(
    _ tuple: (repeat each Prefix, Last)
) -> ((repeat each Prefix), Last) {
    withUnsafeBytes(of: tuple) { ptr in
        let metadata = TupleMetadata((repeat each Prefix, Last).self)
        var iterator = (0..<metadata.count).makeIterator()
        func next<Cast>() -> Cast {
            let element = metadata[iterator.next()!]
            return ptr.load(fromByteOffset: element.offset, as: Cast.self)
        }
        return (
            (repeat { _ in next() } ((each Prefix).self)),
            next()
        )
    }
}

private struct TupleMetadata {
    let pointer: UnsafeRawPointer
    init(_ type: Any.Type) {
        pointer = unsafeBitCast(type, to: UnsafeRawPointer.self)
    }
    var count: Int {
        pointer
            .advanced(by: pointerSize)
            .load(as: Int.self)
    }
    subscript(position: Int) -> Element {
        Element(
            pointer:
                pointer
                .advanced(by: pointerSize)
                .advanced(by: pointerSize)
                .advanced(by: pointerSize)
                .advanced(by: position * 2 * pointerSize)
        )
    }
    struct Element {
        let pointer: UnsafeRawPointer
        var offset: Int { pointer.load(fromByteOffset: pointerSize, as: Int.self) }
    }
}

private let pointerSize = MemoryLayout<UnsafeRawPointer>.size
