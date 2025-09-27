import Foundation

public struct QueryHash: Hashable {
    let value: Int

    public init<each T: Component>(_ query: Query<repeat each T>) {
        var hasher = Hasher()
        hasher.combine(query.signature)
        hasher.combine(query.excludedSignature)
        self.value = hasher.finalize()
    }

    public init(include: ComponentSignature, exclude: ComponentSignature) {
        var hasher = Hasher()
        hasher.combine(include)
        hasher.combine(exclude)
        self.value = hasher.finalize()
    }
}

@usableFromInline
struct SparseQueryPlan {
    @usableFromInline
    let base: ContiguousArray<SlotIndex>
    @usableFromInline
    let others: [ContiguousArray<Array.Index?>] // entityToComponents maps
    @usableFromInline
    let excluded: [ContiguousArray<Array.Index?>]
    @usableFromInline
    let version: UInt64

    @usableFromInline
    init(
        base: ContiguousArray<SlotIndex>,
        others: [ContiguousArray<Array.Index?>],
        excluded: [ContiguousArray<Array.Index?>],
        version: UInt64
    ) {
        self.base = base
        self.others = others
        self.excluded = excluded
        self.version = version
    }
}

@usableFromInline
struct SignatureQueryPlan {
    @usableFromInline
    let base: ContiguousArray<SlotIndex>
    @usableFromInline
    let version: UInt64

    @usableFromInline
    init(
        base: ContiguousArray<SlotIndex>,
        version: UInt64
    ) {
        self.base = base
        self.version = version
    }
}

extension TypedAccess {
    @inlinable @inline(__always)
    static var empty: TypedAccess {
        // a harmless instance that never resolves anything
        TypedAccess(
            buffer: UnsafeMutableBufferPointer(start: nil, count: 0),
            indices: []
        )
    }
}

public struct LazyQuerySequence<each T: Component>: Sequence {
    @usableFromInline
    internal let entityIDs: [Entity.ID]

    @usableFromInline
    internal let accessors: (repeat TypedAccess<(each T).QueriedComponent>)

    @inlinable @inline(__always)
    init(entityIDs: [Entity.ID], accessors: repeat TypedAccess<(each T).QueriedComponent>) {
        self.entityIDs = entityIDs
        self.accessors = (repeat each accessors)
    }

    @inlinable @inline(__always)
    init() {
        self.entityIDs = []
        self.accessors = (repeat TypedAccess<(each T).QueriedComponent>.empty)
    }

    @inlinable @inline(__always)
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

public struct LazyWritableQuerySequence<each T: Component>: Sequence {
    @usableFromInline
    internal let entityIDs: [Entity.ID]

    @usableFromInline
    internal let accessors: (repeat TypedAccess<(each T).QueriedComponent>)

    @inlinable @inline(__always)
    init(entityIDs: [Entity.ID], accessors: repeat TypedAccess<(each T).QueriedComponent>) {
        self.entityIDs = entityIDs
        self.accessors = (repeat each accessors)
    }

    @inlinable @inline(__always)
    init() {
        self.entityIDs = []
        self.accessors = (repeat TypedAccess<(each T).QueriedComponent>.empty)
    }

    @inlinable @inline(__always)
    public func makeIterator() -> AnyIterator<(repeat (each T).ResolvedType)> {
        var index = 0
        return AnyIterator {
            guard index < entityIDs.count else { return nil }
            let id = entityIDs[index]
            index += 1
            return (repeat (each T).makeResolved(access: each accessors, entityID: id))
        }
    }
}

/// Contains all queried components for one entity in a combination query.
/// - Note: This type only exists as a fix for the compiler, since just returning every component or two tuples crashes the build.
@dynamicMemberLookup
public struct CombinationPack<each T>: ~Copyable {
    @inline(__always)
    public let values: (repeat each T)

    @inlinable @inline(__always)
    public init(_ values: (repeat each T)) {
        self.values = values
    }

    public subscript<R>(dynamicMember keyPath: KeyPath<(repeat each T), R>) -> R {
        _read {
            yield values[keyPath: keyPath]
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

    @inline(__always)
    let hash: QueryHash

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
        self.hash = QueryHash(include: signature, exclude: excludedSignature)
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
    -> (base: ContiguousArray<SlotIndex>, others: [ContiguousArray<Array.Index?>], excluded: [ContiguousArray<Array.Index?>])?
    {
        if
            let cached = coordinator.sparseQueryCache[hash],
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
            coordinator.sparseQueryCache[hash] = SparseQueryPlan(
                base: new.base,
                others: new.others,
                excluded: new.excluded,
                version: coordinator.worldVersion
            )
            return new
        }
    }

    @usableFromInline @inline(__always)
    internal func getBaseSparseList(_ coordinator: inout Coordinator) -> ContiguousArray<SlotIndex>? {
        if
            let cached = coordinator.signatureQueryCache[hash],
            cached.version == coordinator.worldVersion
        {
            return cached.base
        } else {
            guard let new = coordinator.pool.base(
                repeat (each T).QueriedComponent.self,
                included: backstageComponents
            ) else {
                return nil
            }
            coordinator.signatureQueryCache[hash] = SignatureQueryPlan(
                base: new,
                version: coordinator.worldVersion
            )
            return new
        }
    }

    // TODO: EnTT groups can just use Array.partition(by:)?

    @inlinable @inline(__always)
    public func performCombinations(
        _ coordinator: inout Coordinator,
        _ handler: (consuming CombinationPack<repeat (each T).ResolvedType>, consuming CombinationPack<repeat (each T).ResolvedType>) -> Void
    ) {
        guard let (baseSlots, otherComponents, excludedComponents) = getArrays(&coordinator) else { return }

        withUnsafeMutablePointer(to: &coordinator) {
            nonisolated(unsafe) let coordinator = $0
            withTypedBuffers(&coordinator.pointee.pool) { (accessors: repeat TypedAccess<(each T).QueriedComponent>) in
                slotALoop: for slotAIndex in baseSlots.startIndex..<baseSlots.endIndex {
                    let slotA = baseSlots[slotAIndex]
                    let slotRaw = slotA.rawValue

                    for component in otherComponents where !component.indices.contains(slotRaw) || component[slotRaw] == nil {
                        // Entity does not have all required components, skip.
                        continue slotALoop
                    }
                    for component in excludedComponents where component.indices.contains(slotRaw) && component[slotRaw] != nil {
                        // Entity has at least one excluded component, skip.
                        continue slotALoop
                    }
                    let idA = Entity.ID(
                        slot: SlotIndex(rawValue: slotRaw),
                        generation: coordinator.pointee.indices[generationFor: slotA]
                    )

                    slotBLoop: for slotBIndex in (slotAIndex + 1)..<baseSlots.endIndex {
                        let slotB = baseSlots[slotBIndex]
                        let slotRaw = slotB.rawValue

                        for component in otherComponents where !component.indices.contains(slotRaw) || component[slotRaw] == nil {
                            // Entity does not have all required components, skip.
                            continue slotBLoop
                        }
                        for component in excludedComponents where component.indices.contains(slotRaw) && component[slotRaw] != nil {
                            // Entity has at least one excluded component, skip.
                            continue slotBLoop
                        }
                        let idB = Entity.ID(
                            slot: SlotIndex(rawValue: slotRaw),
                            generation: coordinator.pointee.indices[generationFor: slotB]
                        )
                        handler(
                            CombinationPack((repeat (each T).makeResolved(access: each accessors, entityID: idA))),
                            CombinationPack((repeat (each T).makeResolved(access: each accessors, entityID: idB)))
                        )
                    }
                }
            }
        }
    }

    @inlinable @inline(__always)
    public func perform(_ coordinator: inout Coordinator, _ handler: (repeat (each T).ResolvedType) -> Void) {
        guard let (baseSlots, otherComponents, excludedComponents) = getArrays(&coordinator) else { return }

        withUnsafeMutablePointer(to: &coordinator) {
            nonisolated(unsafe) let coordinator = $0
            withTypedBuffers(&coordinator.pointee.pool) { (
                accessors: repeat TypedAccess<(each T).QueriedComponent>
            ) in
                slotLoop: for slot in baseSlots {
                    let slotRaw = slot.rawValue

                    for component in otherComponents where !component.indices.contains(slotRaw) || component[slotRaw] == nil {
                        // Entity does not have all required components, skip.
                        continue slotLoop
                    }
                    for component in excludedComponents where component.indices.contains(slotRaw) && component[slotRaw] != nil {
                        // Entity has at least one excluded component, skip.
                        continue slotLoop
                    }
                    let id = Entity.ID(
                        slot: SlotIndex(rawValue: slotRaw),
                        generation: coordinator.pointee.indices[generationFor: slot]
                    )
                    handler(repeat (each T).makeResolved(access: each accessors, entityID: id))
                }
            }
        }
    }

    // This is just here as an example, signatures will be important for archetypes and groups
    @inlinable @inline(__always)
    public func performWithSignature(_ coordinator: inout Coordinator, _ handler: (repeat (each T).ResolvedType) -> Void) {
        guard let baseSlots = getBaseSparseList(&coordinator) else { return }

        withUnsafeMutablePointer(to: &coordinator) {
            nonisolated(unsafe) let coordinator = $0

            withTypedBuffers(&coordinator.pointee.pool) { (
                accessors: repeat TypedAccess<(each T).QueriedComponent>
            ) in
                let querySignature = self.signature
                let excludedSignature = self.excludedSignature

                slotLoop: for slot in baseSlots {
                    let slotRaw = slot.rawValue
                    let signature = coordinator.pointee.entitySignatures[slotRaw]

                    guard
                        signature.rawHashValue.isSuperset(
                            of: querySignature.rawHashValue,
                            isDisjoint: excludedSignature.rawHashValue
                        )
                    else {
                        continue slotLoop
                    }
                    let id = Entity.ID(
                        slot: SlotIndex(rawValue: slotRaw),
                        generation: coordinator.pointee.indices[generationFor: slot]
                    )
                    handler(repeat (each T).makeResolved(access: each accessors, entityID: id))
                }
            }
        }
    }

    @inlinable @inline(__always)
    public func performParallel(_ coordinator: inout Coordinator, _ handler: @Sendable (repeat (each T).ResolvedType) -> Void) where repeat each T: Sendable {
        let slots = coordinator.pool.slots(repeat (each T).QueriedComponent.self, included: backstageComponents, excluded: excludedComponents)

        withTypedBuffers(&coordinator.pool) { (
            accessors: repeat TypedAccess<(each T).QueriedComponent>
        ) in
            let cores = ProcessInfo.processInfo.processorCount
            let chunkSize = (slots.count + cores - 1) / cores

            withUnsafePointer(to: &coordinator.indices) {
                nonisolated(unsafe) let indices: UnsafePointer<IndexRegistry> = $0
                DispatchQueue.concurrentPerform(iterations: min(cores, slots.count)) { i in
                    let start = i * chunkSize
                    let end = min(start + chunkSize, slots.count)
                    
                    for slot in slots[start..<end] {
                        handler(repeat (each T).makeResolved(
                            access: each accessors,
                            entityID: Entity.ID(slot: slot, generation: indices.pointee[generationFor: slot])
                        ))
                    }
                }
            }
        }
    }

    public func iterAll(_ coordinator: inout Coordinator) -> LazyWritableQuerySequence<repeat each T> {
        let slots = coordinator.pool.slots(
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
            return LazyWritableQuerySequence()
        }

        return LazyWritableQuerySequence(
            entityIDs: slots.map { Entity.ID(slot: $0, generation: coordinator.indices[generationFor: $0]) },
            accessors: repeat each accessors
        )
    }

    public func fetchAll(_ coordinator: inout Coordinator) -> LazyQuerySequence<repeat each T> {
        let slots = coordinator.pool.slots(
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

        return LazyQuerySequence(
            entityIDs: slots.map { Entity.ID(slot: $0, generation: coordinator.indices[generationFor: $0]) },
            accessors: repeat each accessors
        )
    }

    public func fetchOne(_ coordinator: inout Coordinator) -> (repeat (each T).ReadOnlyResolvedType)? {
        var result: (repeat (each T).ReadOnlyResolvedType)? = nil
        let slots = coordinator.pool.slots(
            repeat (each T).QueriedComponent.self,
            included: backstageComponents,
            excluded: excludedComponents
        )
        withTypedBuffers(&coordinator.pool) { (
            accessors: repeat TypedAccess<(each T).QueriedComponent>
        ) in
            for slot in slots {
                result = (
                    repeat (each T).makeReadOnlyResolved(
                        access: each accessors,
                        entityID: Entity.ID(slot: slot, generation: coordinator.indices[generationFor: slot])
                    )
                )
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
            guard tagType.QueriedComponent != Never.self else { continue }
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

struct UnsafeSendable<T>: @unchecked Sendable {
    let value: T
}

public struct TypedAccess<C: Component>: @unchecked Sendable {
    @usableFromInline internal var buffer: UnsafeMutableBufferPointer<C>
    @usableFromInline internal var indices: ContiguousArray<ContiguousArray.Index?>

    @usableFromInline
    init(buffer: UnsafeMutableBufferPointer<C>, indices: ContiguousArray<ContiguousArray.Index?>) {
        self.buffer = buffer
        self.indices = indices
    }

    @inlinable @inline(__always)
    public subscript(_ id: Entity.ID) -> C {
        _read {
            yield buffer[indices[id.slot.rawValue].unsafelyUnwrapped]
        }
        nonmutating _modify {
            yield &buffer[indices[id.slot.rawValue].unsafelyUnwrapped]
        }
    }

    @inlinable @inline(__always)
    public func access(_ id: Entity.ID) -> SingleTypedAccess<C> {
        SingleTypedAccess(buffer: buffer.baseAddress.unsafelyUnwrapped.advanced(by: indices[id.slot.rawValue].unsafelyUnwrapped))
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
public struct Write<C: Component>: WritableComponent, Sendable {
    public static var componentTag: ComponentTag { C.componentTag }

    public typealias Wrapped = C

    @usableFromInline
    nonisolated(unsafe) let access: SingleTypedAccess<C>

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

public struct With<C: Component>: Component, Sendable {
    public static var componentTag: ComponentTag { C.componentTag }

    public typealias Wrapped = C
}

public struct WithEntityID: Component, Sendable {
    public static var componentTag: ComponentTag { ComponentTag(rawValue: -1) }
    public typealias ResolvedType = Entity.ID
    public typealias ReadOnlyResolvedType = Entity.ID
    public typealias QueriedComponent = Never

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

extension Never: Component {
    public static let componentTag = ComponentTag(rawValue: -2)
    public typealias QueriedComponent = Never
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
        guard D.self != Never.self else { return TypedAccess<D>.empty }
        guard let anyArray = pool.components[D.componentTag] else { return nil }
        var result: TypedAccess<D>? = nil
        anyArray.withBuffer(D.self) { buffer, entitiesToIndices in
            result = TypedAccess(buffer: buffer, indices: entitiesToIndices)
            // Escaping the buffer here is bad, but we need a pack splitting in calls and recursive flatten in order to resolve this.
            // The solution would be a recursive function which would recusively call `withBuffer` on the head until the pack is empty, and then call `body` with all the buffers.
            // See: https://forums.swift.org/t/pitch-pack-destructuring-pack-splitting/79388/12
            // See: https://forums.swift.org/t/passing-a-parameter-pack-to-a-function-call-fails-to-compile/72243/15
        }
        return result
    }

    guard let built = buildTuple() else { return nil }
    tuple = built
    return try body(repeat each tuple!)
}


@discardableResult
@usableFromInline
func withTypedBuffers<C1: Component, R>(
    _ pool: inout ComponentPool,
    _ body: (TypedAccess<C1>) throws -> R
) rethrows -> R? {
    guard C1.self != Never.self else {
        return try body(TypedAccess<C1>.empty)
    }
    guard let anyArray = pool.components[C1.componentTag] else {
        return nil
    }
    return try anyArray.withBuffer(C1.self) { buffer, entitiesToIndices in
        let access = TypedAccess(buffer: buffer, indices: entitiesToIndices)
        return try body(access)
    }
}

@discardableResult
@usableFromInline
func withTypedBuffers<C1: Component, C2: Component, R>(
    _ pool: inout ComponentPool,
    _ body: (TypedAccess<C1>, TypedAccess<C2>) throws -> R
) rethrows -> R? {
    @inline(__always)
    func withAccess<X: Component>(_ type: X.Type = X.self, continuation: (TypedAccess<X>) throws -> R?) rethrows -> R? {
        guard X.self != Never.self else {
            return try continuation(TypedAccess<X>.empty)
        }
        guard let anyArray = pool.components[X.componentTag] else {
            return nil
        }
        return try anyArray.withBuffer(X.self) { buffer, entitiesToIndices in
            let access = TypedAccess(buffer: buffer, indices: entitiesToIndices)
            return try continuation(access)
        }
    }

    return try withAccess(C1.self) { access1 in
        try withAccess(C2.self) { access2 in
            try body(access1, access2)
        }
    }
}

@discardableResult
@usableFromInline
func withTypedBuffers<C1: Component, C2: Component, C3: Component, R>(
    _ pool: inout ComponentPool,
    _ body: (TypedAccess<C1>, TypedAccess<C2>, TypedAccess<C3>) throws -> R
) rethrows -> R? {
    @inline(__always)
    func withAccess<X: Component>(_ type: X.Type = X.self, continuation: (TypedAccess<X>) throws -> R?) rethrows -> R? {
        guard X.self != Never.self else {
            return try continuation(TypedAccess<X>.empty)
        }
        guard let anyArray = pool.components[X.componentTag] else {
            return nil
        }
        return try anyArray.withBuffer(X.self) { buffer, entitiesToIndices in
            let access = TypedAccess(buffer: buffer, indices: entitiesToIndices)
            return try continuation(access)
        }
    }

    return try withAccess(C1.self) { access1 in
        try withAccess(C2.self) { access2 in
            try withAccess(C3.self) { access3 in
                try body(access1, access2, access3)
            }
        }
    }
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

