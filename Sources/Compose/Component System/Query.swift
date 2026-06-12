import Foundation

public struct ChangeFilter: Hashable, Sendable {
    public enum Condition: Hashable, Sendable {
        case added
        case changed
        case removed
    }

    public struct ComponentCondition: Hashable, Sendable {
        @usableFromInline
        let tag: ComponentTag
        @usableFromInline
        let condition: Condition
    }

    public enum Expression: Hashable, Sendable {
        case require(ComponentCondition)
        case or(Set<ComponentCondition>)
    }

    @usableFromInline
    let expression: Expression

    @usableFromInline
    init(_ expression: Expression) {
        self.expression = expression
    }
}

/// Contains the results of a query alongside metadata about the available entities.
public struct QueryFetchResult<Result> {
    /// The resolved query output.
    public let results: Result

    /// Indicates whether any entities matched the query's membership rules (ignoring change filters).
    /// When this is `false`, the world currently contains no entities with the requested components.
    public let hasMatches: Bool

    @inlinable @inline(__always)
    public init(results: Result, hasMatches: Bool) {
        self.results = results
        self.hasMatches = hasMatches
    }
}

@usableFromInline
struct ChangeFilterComponentMask: Sendable {
    @usableFromInline
    var mask: ChangeFilterMask
    @usableFromInline
    var isOr: Bool

    @usableFromInline
    init(mask: ChangeFilterMask, isOr: Bool) {
        self.mask = mask
        self.isOr = isOr
    }
}

public struct Query<each T: Component>: Sendable where repeat each T: ComponentResolving {
    /// All components which entities are required to have but will not be included in the query output.
    @inline(__always)
    public let backstageComponents: Set<ComponentTag> // Or witnessComponents?

    /// All components where this query ignores contained entities.
    @inline(__always)
    public let excludedComponents: Set<ComponentTag>

    /// Change filters applied to this query.
    @inline(__always)
    public let changeFilters: Set<ChangeFilter>

    @usableFromInline @inline(__always)
    let changeFilterMasks: [ComponentTag: ChangeFilterComponentMask]

    /// Includes all components where this query touches their storage. This includes reads, writes and backstage components.
    @inline(__always)
    public let signature: ComponentSignature

    /// Includes all components where this query reads from their storage. This excludes writes.
    @inline(__always)
    public let readOnlySignature: ComponentSignature

    /// Includes all components where this query writes to their storage.
    @inline(__always)
    public let writeSignature: ComponentSignature

    /// Includes all components where this query ignores contained entities.
    @inline(__always)
    public let excludedSignature: ComponentSignature

    /// Includes all components which are required but will not be included in the query output.
    @inline(__always)
    public let backstageSignature: ComponentSignature

    @inline(__always)
    public let querySignature: QuerySignature

    @usableFromInline @inline(__always)
    let hash: QueryHash

    @usableFromInline
    let isQueryingForEntityID: Bool
    
    /// True if the query not constrained by any component but is querying for entity IDs.
    /// This could be
    /// `Query { WithEntityID.self }`
    /// or
    /// ```
    /// Query {
    ///     WithEntityID.self
    ///     Optional<…>.self
    /// }
    /// ```
    @usableFromInline
    let isQueryingOnlyForEntityID: Bool

    @usableFromInline
    init(
        backstageComponents: Set<ComponentTag>,
        excludedComponents: Set<ComponentTag>,
        changeFilters: Set<ChangeFilter>,
        isQueryingForEntityID: Bool
    ) {
        precondition(Self.hasUniqueQueriedComponents())
        self.backstageComponents = backstageComponents
        self.backstageSignature = ComponentSignature(backstageComponents)
        self.excludedComponents = excludedComponents
        self.changeFilters = changeFilters
        self.changeFilterMasks = Self.makeChangeFilterMasks(changeFilters)
        // Backstage components are part of the overall signature because the
        // query still needs to filter entities that provide them, even though
        // they are not surfaced in the handler. Including them keeps the
        // caching behaviour consistent across query variants.
        self.signature = Self.makeSignature(backstageComponents: backstageComponents)
        self.readOnlySignature = Self.makeReadSignature(backstageComponents: backstageComponents)
        self.writeSignature = Self.makeWriteSignature()
        self.excludedSignature = ComponentSignature(excludedComponents)
        self.querySignature = QuerySignature(
            write: writeSignature,
            readOnly: readOnlySignature,
            backstage: ComponentSignature(backstageComponents),
            excluded: excludedSignature
        )
        self.hash = QueryHash(include: signature, exclude: excludedSignature)
        self.isQueryingForEntityID = isQueryingForEntityID

        //       This would be true for:
        //       ```
        //       Query { WithEntityID.self }
        //       Query { WithEntityID.self; Optional<…>; With<…>; Without<…> }
        //       ```
        //       E. g.: The parameter pack is only filled with `Never` queried components and/or optionals.
        //       Filters like With, Without, Added, Changed will still apply to the slots check.
        self.isQueryingOnlyForEntityID = isQueryingForEntityID && Self.isUnconstrained()
    }

    static func isUnconstrained() -> Bool {
        for component in repeat (each T).self {
            if component is any OptionalQueriedComponent.Type {
                continue
            }
            guard component.QueriedComponent.self != Never.self else {
                continue
            }
            return false
        }
        return true
    }

    @inlinable @inline(__always)
    public func appending<U>(_ type: U.Type = U.self) -> Query<repeat each T, U> {
        Query<repeat each T, U>(
            backstageComponents: backstageComponents,
            excludedComponents: excludedComponents,
            changeFilters: changeFilters,
            isQueryingForEntityID: isQueryingForEntityID || U.self is WithEntityID.Type
        )
    }

    @inlinable @inline(__always)
    public func withGeneration() -> Query<repeat each T> {
        Query(
            backstageComponents: backstageComponents,
            excludedComponents: excludedComponents,
            changeFilters: changeFilters,
            isQueryingForEntityID: true
        )
    }

    /// Returns a copy of this query that tracks additions and mutations for all queried components.
    ///
    /// - Note: Components that only appear as filters (via `With`/`Without`) and virtual components such as `WithEntityID`
    ///   are ignored.
//    @inlinable @inline(__always)
//    public func tracking() -> Self {
//        var filters = changeFilters
//
//        for component in repeat (each T).QueriedComponent.self {
//            let tag = component.componentTag
//
//            guard tag.rawValue > 0 else { continue }
//            guard backstageComponents.contains(tag) == false else { continue }
//            guard excludedComponents.contains(tag) == false else { continue }
//
//            filters.insert(ChangeFilter(tag: tag, kind: .added))
//            filters.insert(ChangeFilter(tag: tag, kind: .changed))
//        }
//
//        return Query(
//            backstageComponents: backstageComponents,
//            excludedComponents: excludedComponents,
//            changeFilters: filters,
//            isQueryingForEntityID: isQueryingForEntityID
//        )
//    }

    @inlinable @inline(__always)
    public func callAsFunction(_ context: QueryContext, _ handler: (repeat (each T).ResolvedType) -> Void) {
        perform(context, handler)
    }

    @inlinable @inline(__always)
    public func callAsFunction(_ coordinator: Coordinator, _ handler: (repeat (each T).ResolvedType) -> Void) {
        perform(QueryContext(coordinator: coordinator), handler)
    }

    @inlinable @inline(__always)
    public func callAsFunction(signature context: QueryContext, _ handler: (repeat (each T).ResolvedType) -> Void) {
        performWithSignature(context, handler)
    }

    @inlinable @inline(__always)
    public func callAsFunction(signature coordinator: Coordinator, _ handler: (repeat (each T).ResolvedType) -> Void) {
        performWithSignature(QueryContext(coordinator: coordinator), handler)
    }

//    @inlinable @inline(__always)
//    public func callAsFunction(preloaded context: QueryContext, _ handler: (repeat (each T).ResolvedType) -> Void) {
//        performPreloaded(context, handler)
//    }
//
//    @inlinable @inline(__always)
//    public func callAsFunction(preloaded coordinator: Coordinator, _ handler: (repeat (each T).ResolvedType) -> Void) {
//        performPreloaded(QueryContext(coordinator: coordinator), handler)
//    }

    @inlinable @inline(__always)
    public func callAsFunction(parallel context: QueryContext, _ handler: @Sendable (repeat (each T).ResolvedType) -> Void) where repeat each T: Sendable {
        performParallel(context, handler)
    }

    @inlinable @inline(__always)
    public func callAsFunction(parallel coordinator: Coordinator, _ handler: @Sendable (repeat (each T).ResolvedType) -> Void) where repeat each T: Sendable {
        performParallel(QueryContext(coordinator: coordinator), handler)
    }

//    @inlinable @inline(__always)
//    public func callAsFunction(preloadedParallel context: QueryContext, _ handler: @Sendable (repeat (each T).ResolvedType) -> Void) where repeat each T: Sendable {
//        performPreloadedParallel(context, handler)
//    }
//
//    @inlinable @inline(__always)
//    public func callAsFunction(preloadedParallel coordinator: Coordinator, _ handler: @Sendable (repeat (each T).ResolvedType) -> Void) where repeat each T: Sendable {
//        performPreloadedParallel(QueryContext(coordinator: coordinator), handler)
//    }

    @inlinable @inline(__always)
    public func callAsFunction(combinations context: QueryContext, _ handler: (CombinationPack<repeat (each T).ResolvedType>, CombinationPack<repeat (each T).ResolvedType>) -> Void) {
        performCombinations(context, handler)
    }

    @inlinable @inline(__always)
    public func callAsFunction(combinations coordinator: Coordinator, _ handler: (CombinationPack<repeat (each T).ResolvedType>, CombinationPack<repeat (each T).ResolvedType>) -> Void) {
        performCombinations(QueryContext(coordinator: coordinator), handler)
    }

    @inlinable @inline(__always)
    public func callAsFunction(fetchOne context: QueryContext) -> (repeat (each T).ReadOnlyResolvedType)? {
        fetchOne(context)
    }

    @inlinable @inline(__always)
    public func callAsFunction(fetchOne coordinator: Coordinator) -> (repeat (each T).ReadOnlyResolvedType)? {
        fetchOne(QueryContext(coordinator: coordinator))
    }

    @inlinable @inline(__always)
    public func callAsFunction(fetchAll context: QueryContext) -> LazyQuerySequence<repeat each T> {
        fetchAll(context)
    }

    @inlinable @inline(__always)
    public func callAsFunction(fetchAll coordinator: Coordinator) -> LazyQuerySequence<repeat each T> {
        fetchAll(QueryContext(coordinator: coordinator))
    }

    @inlinable @inline(__always)
    public func callAsFunction(unsafeFetchAllWritable context: QueryContext) -> LazyWritableQuerySequence<repeat each T> {
        unsafeFetchAllWritable(context)
    }

    @inlinable @inline(__always)
    public func callAsFunction(unsafeFetchAllWritable coordinator: Coordinator) -> LazyWritableQuerySequence<repeat each T> {
        unsafeFetchAllWritable(QueryContext(coordinator: coordinator))
    }

    @inlinable @inline(__always)
    static func makeSignature(backstageComponents: Set<ComponentTag>) -> ComponentSignature {
        var signature = ComponentSignature()

        for tag in backstageComponents {
            signature = signature.appending(tag)
        }

        for tagType in repeat (each T).self {
            guard
                tagType.QueriedComponent != Never.self,
                tagType is any OptionalQueriedComponent.Type == false
            else {
                continue
            }
            signature = signature.appending(tagType.componentTag)
        }

        return signature
    }

    @inlinable @inline(__always)
    static func makeReadSignature(backstageComponents: Set<ComponentTag>, includeOptionals: Bool = false) -> ComponentSignature {
        var signature = ComponentSignature()

        for tagType in repeat (each T).self {
            guard
                tagType.QueriedComponent != Never.self,
                tagType is any WritableComponent.Type == false,
                (includeOptionals || tagType is any OptionalQueriedComponent.Type == false)
            else {
                continue
            }
            signature = signature.appending(tagType.componentTag)
        }

        return signature
    }

    @inlinable @inline(__always)
    static func makeWriteSignature(includeOptionals: Bool = false) -> ComponentSignature {
        var signature = ComponentSignature()

        for tagType in repeat (each T).self {
            guard
                tagType.QueriedComponent != Never.self,
                tagType is any WritableComponent.Type,
                (includeOptionals || tagType is any OptionalQueriedComponent.Type == false)
            else {
                continue
            }
            signature = signature.appending(tagType.componentTag)
        }

        return signature
    }
}

/// Contains all queried components for one entity in a combination query.
/// - Note: This type only exists as a fix for the compiler, since just returning every component or two tuples crashes the build.
@dynamicMemberLookup
public struct CombinationPack<each T> {
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

extension Query {
    @inlinable @inline(__always)
    public func fetchOne(_ context: some QueryContextConvertible) -> (repeat (each T).ReadOnlyResolvedType)? {
        fetchOneWithStatus(context).results
    }

    @inlinable @inline(__always)
    public func fetchOne(_ coordinator: Coordinator) -> (repeat (each T).ReadOnlyResolvedType)? {
        fetchOneWithStatus(coordinator).results
    }

    @inlinable @inline(__always)
    public func fetchOneWithStatus(_ context: some QueryContextConvertible) -> QueryFetchResult<(repeat (each T).ReadOnlyResolvedType)?> {
        let context = context.queryContext
        var (baseSlots, otherComponents, excludedComponents) = getCachedArrays(context.coordinator)
        let ids = isQueryingOnlyForEntityID ? context.coordinator.indices.liveSlots : []
        defer {
            extendLifetime(ids)
        }
        if baseSlots.isEmpty, isQueryingOnlyForEntityID {
            ids.withUnsafeBufferPointer { buffer in
                baseSlots = ContiguousSpan(view: buffer, count: buffer.count)
            }
        }
        guard !baseSlots.isEmpty else { return QueryFetchResult(results: nil, hasMatches: false) }

        let tickSnapshot = context.systemTickSnapshot
        var hasMatches = false

        let result: (repeat (each T).ReadOnlyResolvedType)? = context.coordinator.indices.generation.withUnsafeBufferPointer { generationsBuffer in
            let generationsPointer = generationsBuffer.baseAddress.unsafelyUnwrapped
            assert(generationsBuffer.count > 0 || baseSlots.count == 0, "Generation buffer is empty but baseSlots has \(baseSlots.count) slots.")
            return withTypedBuffers(&context.coordinator.pool, changeTick: context.coordinator.changeTick) { (accessors: repeat TypedAccess<each T>) in
                otherComponents.withUnsafeBufferPointer { otherBuffer in
                    excludedComponents.withUnsafeBufferPointer { excludedBuffer in
                        let otherPointer = otherBuffer.baseAddress.unsafelyUnwrapped
                        let otherCount = otherBuffer.count
                        let excludedPointer = excludedBuffer.baseAddress.unsafelyUnwrapped
                        let excludedCount = excludedBuffer.count
                        guard let strategy = prepareChangeFilterAccessors((repeat each accessors), pool: &context.coordinator.pool) else {
                            return nil
                        }
                        switch strategy {
                        case .none:
                            for slot in baseSlots where Self.passesMembership(
                                slot,
                                otherBuffer: otherPointer,
                                otherCount: otherCount,
                                excludedBuffer: excludedPointer,
                                excludedCount: excludedCount
                            ) {
                                hasMatches = true

                                let entityID = Entity.ID(slot: slot, generation: isQueryingForEntityID ? generationsPointer[slot.rawValue] : 0)
                                return (
                                    repeat (each T).makeReadOnlyResolved(
                                        access: each accessors,
                                        entityID: entityID
                                    )
                                )
                            }
                        case .fast(let changeFilters):
                            return changeFilters.withUnsafeBufferPointer { changeBuffer in
                                let changePointer = changeBuffer.baseAddress.unsafelyUnwrapped
                                let changeCount = changeBuffer.count
                                let lastRun = tickSnapshot.lastRun
                                let thisRun = tickSnapshot.thisRun
                                let addedMask = ChangeFilterMask.added.rawValue
                                let changedMask = ChangeFilterMask.changed.rawValue
                                let removedMask = ChangeFilterMask.removed.rawValue

                                for slot in baseSlots {
                                    switch Self.passes(
                                        slot: slot,
                                        requiredComponents: otherPointer,
                                        requiredComponentsCount: otherCount,
                                        excludedComponents: excludedPointer,
                                        excludedComponentsCount: excludedCount,
                                        changeFilters: changePointer,
                                        changeFiltersCount: changeCount,
                                        addedMask: addedMask,
                                        changedMask: changedMask,
                                        removedMask: removedMask,
                                        lastRun: lastRun,
                                        thisRun: thisRun,
                                        generations: generationsPointer,
                                        generationsCount: generationsBuffer.count
                                    ) {
                                    case .passes:
                                        hasMatches = true
                                        let entityID = Entity.ID(slot: slot, generation: isQueryingForEntityID ? generationsPointer[slot.rawValue] : 0)
                                        return (
                                            repeat (each T).makeReadOnlyResolved(
                                                access: each accessors,
                                                entityID: entityID
                                            )
                                        )
                                    case .filteredByChanges:
                                        hasMatches = true
                                        continue
                                    case .noMatch:
                                        continue
                                    }
                                }

                                return nil
                            }
                        }

                        return nil
                    }
                }
            }
        }

        return QueryFetchResult(results: result, hasMatches: hasMatches)
    }

    @inlinable @inline(__always)
    public func fetchOneWithStatus(_ coordinator: Coordinator) -> QueryFetchResult<(repeat (each T).ReadOnlyResolvedType)?> {
        fetchOneWithStatus(QueryContext(coordinator: coordinator))
    }
}

extension Query {
    @inlinable @inline(__always)
    public func fetchAll(_ context: some QueryContextConvertible) -> LazyQuerySequence<repeat each T> {
        fetchAllWithStatus(context).results
    }

    @inlinable @inline(__always)
    public func fetchAll(_ coordinator: Coordinator) -> LazyQuerySequence<repeat each T> {
        fetchAllWithStatus(coordinator).results
    }

    @inlinable @inline(__always)
    public func fetchAllWithStatus(_ context: some QueryContextConvertible) -> QueryFetchResult<LazyQuerySequence<repeat each T>> {
        let context = context.queryContext
        var (baseSlots, otherComponents, excludedComponents) = getCachedArrays(context.coordinator)
        // Hoisted to outer scope: `ids` must outlive `baseSlots`, because
        // ContiguousSpan is a non-owning view of the array's buffer.
        let ids = isQueryingOnlyForEntityID ? context.coordinator.indices.liveSlots : []
        defer {
            // `extendLifetime` keeps `ids` alive while baseSlots (a non-owning ContiguousSpan into ids' buffer) is iterated.
            extendLifetime(ids)
        }
        if baseSlots.isEmpty, isQueryingOnlyForEntityID {
            // This is for cases like `Query { WithEntityID.self }` or `Query { WithEntityID.self; Optional<…>.self }`
            ids.withUnsafeBufferPointer { buffer in
                baseSlots = ContiguousSpan(view: buffer, count: buffer.count)
            }
        }
        guard !baseSlots.isEmpty else { return QueryFetchResult(results: LazyQuerySequence(), hasMatches: false) }

        let tickSnapshot = context.systemTickSnapshot
        var hasMatches = false

        let accessors = withTypedBuffers(&context.coordinator.pool, changeTick: context.coordinator.changeTick) { (accessors: repeat TypedAccess<each T>) in
            (repeat each accessors)
        }

        let entitiesAndMatch: (hasMatches: Bool, entities: [Entity.ID]) = context.coordinator.indices.generation.withUnsafeBufferPointer { generationsBuffer in
            let generationsPointer = generationsBuffer.baseAddress.unsafelyUnwrapped
            assert(generationsBuffer.count > 0 || baseSlots.count == 0, "Generation buffer is empty but baseSlots has \(baseSlots.count) slots.")
            return otherComponents.withUnsafeBufferPointer { otherBuffer in
                excludedComponents.withUnsafeBufferPointer { excludedBuffer in
                    let otherPointer = otherBuffer.baseAddress.unsafelyUnwrapped
                    let otherCount = otherBuffer.count
                    let excludedPointer = excludedBuffer.baseAddress.unsafelyUnwrapped
                    let excludedCount = excludedBuffer.count
                    guard let strategy = prepareChangeFilterAccessors((repeat each accessors), pool: &context.coordinator.pool) else {
                        return (false, [])
                    }
                    var entities: [Entity.ID] = []
                    entities.reserveCapacity(baseSlots.count)
                    switch strategy {
                    case .none:
                        for slot in baseSlots where Self.passesMembership(
                            slot,
                            otherBuffer: otherPointer,
                            otherCount: otherCount,
                            excludedBuffer: excludedPointer,
                            excludedCount: excludedCount
                        ) {
                            hasMatches = true
                            let entityID = Entity.ID(slot: slot, generation: isQueryingForEntityID ? generationsPointer[slot.rawValue] : 0)
                            entities.append(entityID)
                        }
                        return (hasMatches, entities)

                    case .fast(let changeFilters):
                        return changeFilters.withUnsafeBufferPointer { changeBuffer in
                            let changePointer = changeBuffer.baseAddress.unsafelyUnwrapped
                            let changeCount = changeBuffer.count
                            let lastRun = tickSnapshot.lastRun
                            let thisRun = tickSnapshot.thisRun
                            let addedMask = ChangeFilterMask.added.rawValue
                            let changedMask = ChangeFilterMask.changed.rawValue
                            let removedMask = ChangeFilterMask.removed.rawValue
                            for slot in baseSlots {
                                switch Self.passes(
                                    slot: slot,
                                    requiredComponents: otherPointer,
                                    requiredComponentsCount: otherCount,
                                    excludedComponents: excludedPointer,
                                    excludedComponentsCount: excludedCount,
                                    changeFilters: changePointer,
                                    changeFiltersCount: changeCount,
                                    addedMask: addedMask,
                                    changedMask: changedMask,
                                    removedMask: removedMask,
                                    lastRun: lastRun,
                                    thisRun: thisRun,
                                    generations: generationsPointer,
                                    generationsCount: generationsBuffer.count
                                ) {
                                case .passes:
                                    hasMatches = true
                                    let entityID = Entity.ID(slot: slot, generation: isQueryingForEntityID ? generationsPointer[slot.rawValue] : 0)
                                    entities.append(entityID)
                                case .filteredByChanges:
                                    hasMatches = true
                                    continue
                                case .noMatch:
                                    continue
                                }
                            }

                            return (hasMatches, entities)
                        }
                    }
                }
            }
        }

        return QueryFetchResult(
            results: LazyQuerySequence(
                entityIDs: entitiesAndMatch.entities,
                accessors: repeat each accessors
            ),
            hasMatches: entitiesAndMatch.hasMatches
        )
    }

    @inlinable @inline(__always)
    public func fetchAllWithStatus(_ coordinator: Coordinator) -> QueryFetchResult<LazyQuerySequence<repeat each T>> {
        fetchAllWithStatus(QueryContext(coordinator: coordinator))
    }
}

extension Query {
//    @inlinable @inline(__always)
//    public func performPreloadedParallel(_ context: some QueryContextConvertible, _ handler: @Sendable (repeat (each T).ResolvedType) -> Void) where repeat each T: Sendable {
//        let context = context.queryContext
//        let slots = getCachedPreFilteredSlots(context.coordinator)
//        let tickSnapshot = context.systemTickSnapshot
//        withTypedBuffers(&context.coordinator.pool, changeTick: context.coordinator.changeTick) { (accessors: repeat TypedAccess<each T>) in
//            let fastChangeAccessors = changeFilterMasks.isEmpty
//                ? nil
//                : prepareChangeFilterAccessors((repeat each accessors))
//            let cores = ProcessInfo.processInfo.processorCount
//            let chunkSize = max(1, (slots.count + cores - 1) / cores) // ceil division
//            let chunks = (slots.count + chunkSize - 1) / chunkSize // ceil number of chunks
//
//            withUnsafePointer(to: &context.coordinator.indices) {
//                nonisolated(unsafe) let indices: UnsafePointer<IndexRegistry> = $0
//                DispatchQueue.concurrentPerform(iterations: chunks) { i in
//                    let start = i * chunkSize
//                    let end = min(start + chunkSize, slots.count)
//                    if start >= end { return } // guard against empty/invalid slice
//
//                    for slot in slots[start..<end] {
//                        let generation = indices.pointee[generationFor: slot]
//                        let fullID = Entity.ID(slot: slot, generation: generation)
//                        if !entitySatisfiesChangeFilters(
//                            context,
//                            systemTickSnapshot: tickSnapshot,
//                            fastAccessors: fastChangeAccessors,
//                            entityID: fullID
//                        ) { continue }
//                        let entityID = isQueryingForEntityID ? fullID : Entity.ID(slot: slot, generation: 0)
//                        handler(repeat (each T).makeResolved(
//                            access: each accessors,
//                            entityID: entityID
//                        ))
//                    }
//                }
//            }
//        }
//    }
}

extension Query {
    @inlinable @inline(__always)
    public func performParallel(_ context: some QueryContextConvertible, _ handler: @Sendable (repeat (each T).ResolvedType) -> Void) where repeat each T: Sendable {
        let context = context.queryContext
        var slots = getCachedBaseSlots(context.coordinator)
        let ids = isQueryingOnlyForEntityID ? context.coordinator.indices.liveSlots : []
        defer {
            extendLifetime(ids)
        }
        if slots.isEmpty, isQueryingOnlyForEntityID {
            ids.withUnsafeBufferPointer { buffer in
                slots = ContiguousSpan(view: buffer, count: buffer.count)
            }
        }
        guard !slots.isEmpty else { return }
        let tickSnapshot = context.systemTickSnapshot
        withTypedBuffers(&context.coordinator.pool, changeTick: context.coordinator.changeTick) { (accessors: repeat TypedAccess<each T>) in
            guard let strategy = prepareChangeFilterAccessors((repeat each accessors), pool: &context.coordinator.pool) else {
                return
            }
            let querySignature = self.signature
            let excludedSignature = self.excludedSignature
            let generations = context.coordinator.indices.generationView
            let signatures = context.coordinator.entitySignaturesView

            let cores = ProcessInfo.processInfo.processorCount
            let chunkSize = max(1, (slots.count + cores - 1) / cores) // ceil division
            let chunks = (slots.count + chunkSize - 1) / chunkSize // ceil number of chunks

            switch strategy {
            case .none:
                DispatchQueue.concurrentPerform(iterations: chunks) { i in
                    let start = i * chunkSize
                    let end = min(start + chunkSize, slots.count)
                    if start >= end { return } // guard against empty/invalid slice

                    for slot in slots[start..<end] {
                        let signature = signatures[slot]
                        guard
                            signature.rawHashValue.isSuperset(
                                of: querySignature.rawHashValue,
                                isDisjoint: excludedSignature.rawHashValue
                            )
                        else {
                            continue
                        }

                        let entityID = Entity.ID(
                            slot: slot,
                            generation: isQueryingForEntityID ? generations[slot] : 0
                        )
                        handler(repeat (each T).makeResolved(access: each accessors, entityID: entityID))
                    }
                }
            case .fast(let changeFilters):
                let lastRun = tickSnapshot.lastRun
                let thisRun = tickSnapshot.thisRun
                let addedMask = ChangeFilterMask.added.rawValue
                let changedMask = ChangeFilterMask.changed.rawValue
                let removedMask = ChangeFilterMask.removed.rawValue
                changeFilters.withUnsafeBufferPointer { changeFiltersBuffer in
                    let changeFiltersPointer = changeFiltersBuffer.baseAddress.unsafelyUnwrapped
                    let changeFiltersCount = changeFiltersBuffer.count

                    DispatchQueue.concurrentPerform(iterations: chunks) { i in
                        let start = i * chunkSize
                        let end = min(start + chunkSize, slots.count)
                        if start >= end { return } // guard against empty/invalid slice

                        for slot in slots[start..<end] {
                            let signature = signatures[slot]
                            guard
                                signature.rawHashValue.isSuperset(
                                    of: querySignature.rawHashValue,
                                    isDisjoint: excludedSignature.rawHashValue
                                ),
                                Self.passesChangeFilters(
                                    slot,
                                    buffer: changeFiltersPointer,
                                    bufferCount: changeFiltersCount,
                                    addedMask: addedMask,
                                    changedMask: changedMask,
                                    removedMask: removedMask,
                                    lastRun: lastRun,
                                    thisRun: thisRun,
                                    generations: generations.pointer
                                )
                            else {
                                continue
                            }

                            let entityID = Entity.ID(
                                slot: slot,
                                generation: isQueryingForEntityID ? generations[slot] : 0
                            )
                            handler(repeat (each T).makeResolved(access: each accessors, entityID: entityID))
                        }
                    }
                }
            }
        }
    }
}

extension Query {
    // This is just here as an example, signatures will be important for archetypes and groups
    @inlinable @inline(__always)
    public func performWithSignature(_ context: some QueryContextConvertible, _ handler: (repeat (each T).ResolvedType) -> Void) {
        let context = context.queryContext
        var baseSlots = getCachedBaseSlots(context.coordinator)
        let ids = isQueryingOnlyForEntityID ? context.coordinator.indices.liveSlots : []
        defer {
            extendLifetime(ids)
        }
        if baseSlots.isEmpty, isQueryingOnlyForEntityID {
            ids.withUnsafeBufferPointer { buffer in
                baseSlots = ContiguousSpan(view: buffer, count: buffer.count)
            }
        }
        guard !baseSlots.isEmpty else { return }

        let baseCount = baseSlots.count
        guard baseCount > 0 else { return }
        let basePointer = baseSlots.buffer

        let tickSnapshot = context.systemTickSnapshot
        let indices = context.coordinator.indices.generationView
        let signatures = context.coordinator.entitySignaturesView
        let querySignature = self.signature
        withTypedBuffers(&context.coordinator.pool, changeTick: context.coordinator.changeTick) { (accessors: repeat TypedAccess<each T>) in
            guard let strategy = prepareChangeFilterAccessors((repeat each accessors), pool: &context.coordinator.pool) else {
                return
            }

            let indicesPointer = indices.pointer

            switch strategy {
            case .none:
                @inline(__always) @_transparent
                func run(_ id: (SlotIndex) -> Entity.ID) {
                    var baseIndex = 0
                    while baseIndex < baseCount {
                        let slot = basePointer.advanced(by: baseIndex).pointee
                        baseIndex &+= 1

                        let signature = signatures[slot]
                        guard
                            signature.rawHashValue.isSuperset(
                                of: querySignature.rawHashValue,
                                isDisjoint: excludedSignature.rawHashValue
                            )
                        else {
                            continue
                        }

                        let entityID = id(slot)

                        handler(repeat (each T).makeResolved(access: each accessors, entityID: entityID))
                    }
                }
                if isQueryingForEntityID {
                    run {
                        Entity.ID(
                            slot: $0,
                            generation: indicesPointer.advanced(by: $0.rawValue).pointee
                        )
                    }
                } else {
                    run {
                        Entity.ID(slot: $0, generation: 0)
                    }
                }

            case .fast(let fastChangeAccessors):
                let lastRun = tickSnapshot.lastRun
                let thisRun = tickSnapshot.thisRun
                let addedMask = ChangeFilterMask.added.rawValue
                let changedMask = ChangeFilterMask.changed.rawValue
                let removedMask = ChangeFilterMask.removed.rawValue

                fastChangeAccessors.withUnsafeBufferPointer { changeBuffer in
                    let changeCount = changeBuffer.count
                    let changePointer = changeBuffer.baseAddress.unsafelyUnwrapped

                    var baseIndex = 0
                    while baseIndex < baseCount {
                        let slot = basePointer.advanced(by: baseIndex).pointee
                        baseIndex &+= 1

                        guard
                            signatures[slot].rawHashValue.isSuperset(
                                of: querySignature.rawHashValue,
                                isDisjoint: excludedSignature.rawHashValue
                            ),
                            Self.passesChangeFilters(
                                slot,
                                buffer: changePointer,
                                bufferCount: changeCount,
                                addedMask: addedMask,
                                changedMask: changedMask,
                                removedMask: removedMask,
                                lastRun: lastRun,
                                thisRun: thisRun,
                                generations: indicesPointer
                            )
                        else {
                            continue
                        }

                        let entityID = Entity.ID(
                            slot: slot,
                            generation: isQueryingForEntityID ? indicesPointer.advanced(by: slot.rawValue).pointee : 0
                        )

                        handler(repeat (each T).makeResolved(access: each accessors, entityID: entityID))
                    }
                }
            }
        }
    }
}

extension Query {
    @inlinable @inline(__always)
    public func performCombinations(
        _ context: some QueryContextConvertible,
        _ handler: (CombinationPack<repeat (each T).ResolvedType>, CombinationPack<repeat (each T).ResolvedType>) -> Void
    ) {
        let context = context.queryContext
        var (baseSlots, otherComponents, excludedComponents) = getCachedArrays(context.coordinator)
        let ids = isQueryingOnlyForEntityID ? context.coordinator.indices.liveSlots : []
        defer {
            extendLifetime(ids)
        }
        if baseSlots.isEmpty, isQueryingOnlyForEntityID {
            ids.withUnsafeBufferPointer { buffer in
                baseSlots = ContiguousSpan(view: buffer, count: buffer.count)
            }
        }
        guard !baseSlots.isEmpty else { return }
        // TODO: Use RigidArray or TailAllocated here

        let baseCount = baseSlots.count
        guard baseCount > 0 else { return }
        let basePointer = baseSlots.buffer

        let tickSnapshot = context.systemTickSnapshot
        let indices = context.coordinator.indices.generationView
        withTypedBuffers(&context.coordinator.pool, changeTick: context.coordinator.changeTick) { (accessors: repeat TypedAccess<each T>) in
            guard let strategy = prepareChangeFilterAccessors((repeat each accessors), pool: &context.coordinator.pool) else {
                return
            }

            let indicesPointer = indices.pointer
            let otherCount = otherComponents.count
            let excludedCount = excludedComponents.count

            var resolved: [CombinationPack<repeat (each T).ResolvedType>] = []
            resolved.reserveCapacity(baseSlots.count)

            otherComponents.withUnsafeBufferPointer { otherBuffer in
                excludedComponents.withUnsafeBufferPointer { excludedBuffer in
                    let otherPointer = otherBuffer.baseAddress.unsafelyUnwrapped
                    let excludedPointer = excludedBuffer.baseAddress.unsafelyUnwrapped

                    switch strategy {
                    case .none:
                        @inline(__always) @_transparent
                        func run(_ id: (SlotIndex) -> Entity.ID) {
                            var baseIndex = 0
                            while baseIndex < baseCount {
                                let slot = basePointer.advanced(by: baseIndex).pointee
                                baseIndex &+= 1

                                guard Self.passesMembership(
                                    slot,
                                    otherBuffer: otherPointer,
                                    otherCount: otherCount,
                                    excludedBuffer: excludedPointer,
                                    excludedCount: excludedCount
                                ) else {
                                    continue
                                }

                                let entityID = id(slot)
                                let pack = CombinationPack((repeat (each T).makeResolved(access: each accessors, entityID: entityID)))
                                resolved.append(pack)
                            }
                        }
                        if isQueryingForEntityID {
                            run {
                                Entity.ID(
                                    slot: $0,
                                    generation: indicesPointer.advanced(by: $0.rawValue).pointee
                                )
                            }
                        } else {
                            run {
                                Entity.ID(slot: $0, generation: 0)
                            }
                        }

                    case .fast(let fastChangeAccessors):
                        let lastRun = tickSnapshot.lastRun
                        let thisRun = tickSnapshot.thisRun
                        let addedMask = ChangeFilterMask.added.rawValue
                        let changedMask = ChangeFilterMask.changed.rawValue
                        let removedMask = ChangeFilterMask.removed.rawValue

                        fastChangeAccessors.withUnsafeBufferPointer { changeBuffer in
                            let changeCount = changeBuffer.count
                            let changePointer = changeBuffer.baseAddress.unsafelyUnwrapped

                            var baseIndex = 0
                            while baseIndex < baseCount {
                                let slot = basePointer.advanced(by: baseIndex).pointee
                                baseIndex &+= 1

                                guard
                                    Self.passesMembership(
                                        slot,
                                        otherBuffer: otherPointer,
                                        otherCount: otherCount,
                                        excludedBuffer: excludedPointer,
                                        excludedCount: excludedCount
                                    ),
                                    Self.passesChangeFilters(
                                        slot,
                                        buffer: changePointer,
                                        bufferCount: changeCount,
                                        addedMask: addedMask,
                                        changedMask: changedMask,
                                        removedMask: removedMask,
                                        lastRun: lastRun,
                                        thisRun: thisRun,
                                        generations: indicesPointer
                                    )
                                else {
                                    continue
                                }

                                let entityID = Entity.ID(
                                    slot: slot,
                                    generation: isQueryingForEntityID ? indicesPointer.advanced(by: slot.rawValue).pointee : 0
                                )

                                let pack = CombinationPack((repeat (each T).makeResolved(access: each accessors, entityID: entityID)))
                                resolved.append(pack)
                            }
                        }
                    }
                }
            }

            for i in 0..<resolved.count {
                for j in i+1..<resolved.count {
                    handler(
                        resolved[i],
                        resolved[j]
                    )
                }
            }
        }
    }
}

@usableFromInline
struct ChangeFilterMask: OptionSet, Sendable {
    @usableFromInline
    let rawValue: UInt8

    @inlinable @inline(__always)
    init(rawValue: UInt8) {
        self.rawValue = rawValue
    }

    @usableFromInline
    static let added = ChangeFilterMask(rawValue: 1 << 1)

    @usableFromInline
    static let changed = ChangeFilterMask(rawValue: 1 << 2)

    @usableFromInline
    static let removed = ChangeFilterMask(rawValue: 1 << 3)
}

@usableFromInline
struct ChangeFilterAccessor {
    @usableFromInline
    let mask: ChangeFilterMask
    @usableFromInline
    let isOr: Bool
    @usableFromInline
    let indices: SlotsSpan<ContiguousArray.Index, SlotIndex>
    @usableFromInline
    let ticks: MutableContiguousSpan<ComponentTicks>

    @usableFromInline
    init(mask: ChangeFilterMask, isOr: Bool, indices: SlotsSpan<ContiguousArray.Index, SlotIndex>, ticks: MutableContiguousSpan<ComponentTicks>) {
        self.mask = mask
        self.isOr = isOr
        self.indices = indices
        self.ticks = ticks
    }
}

@usableFromInline
enum ChangeFilterStrategy {
    case none
    case fast(ContiguousArray<ChangeFilterAccessor>)
}

@usableFromInline
enum PassResult: UInt8 {
    case noMatch
    case filteredByChanges
    case passes
}

extension Query {
    @inlinable @inline(__always)
    static func hasUniqueQueriedComponents() -> Bool {
        var seen = ComponentSignature()
        for queried in repeat (each T).self {
            guard queried.QueriedComponent.componentTag.rawValue > 0 else { continue }
            guard !seen.contains(queried.QueriedComponent.componentTag) else {
                return false
            }
            seen.append(queried.QueriedComponent.componentTag)
        }
        return true
    }

    @inlinable @inline(__always)
    static func makeChangeFilterMasks(_ filters: Set<ChangeFilter>) -> [ComponentTag: ChangeFilterComponentMask] {
        guard !filters.isEmpty else { return [:] }
        var masks: [ComponentTag: ChangeFilterComponentMask] = [:]
        masks.reserveCapacity(filters.count)
        for filter in filters {
            switch filter.expression {
            case .require(let condition):
                var mask = masks[condition.tag] ?? ChangeFilterComponentMask(mask: [], isOr: false)
                mask.isOr = false
                switch condition.condition {
                case .added:
                    mask.mask.insert(.added)
                case .changed:
                    mask.mask.insert(.changed)
                case .removed:
                    mask.mask.insert(.removed)
                }
                masks[condition.tag] = mask
            case .or(let conditions):
                for condition in conditions {
                    var mask = masks[condition.tag] ?? ChangeFilterComponentMask(mask: [], isOr: true)
                    switch condition.condition {
                    case .added:
                        mask.mask.insert(.added)
                    case .changed:
                        mask.mask.insert(.changed)
                    case .removed:
                        mask.mask.insert(.removed)
                    }
                    masks[condition.tag] = mask
                }
            }
        }
        return masks
    }

    @inlinable @inline(__always)
    static func makeChangeFilterOrMasks(_ filters: Set<ChangeFilter>) -> [ComponentTag: ChangeFilterMask] {
        guard !filters.isEmpty else { return [:] }
        var masks: [ComponentTag: ChangeFilterMask] = [:]
        masks.reserveCapacity(filters.count)
        for filter in filters {
            switch filter.expression {
            case .require(let condition):
                break
            case .or(let conditions):
                for condition in conditions {
                    var mask = masks[condition.tag] ?? []
                    switch condition.condition {
                    case .added:
                        mask.insert(.added)
                    case .changed:
                        mask.insert(.changed)
                    case .removed:
                        mask.insert(.removed)
                    }
                    masks[condition.tag] = mask
                }
            }
        }
        return masks
    }

    @inlinable @inline(__always)
    func prepareChangeFilterAccessors(
        _ accessors: (repeat TypedAccess<each T>),
        pool: UnsafePointer<ComponentPool>
    ) -> ChangeFilterStrategy? {
        guard !changeFilterMasks.isEmpty else { return ChangeFilterStrategy.none }

        var remaining = ComponentSignature(changeFilterMasks.keys)
        var prepared: ContiguousArray<ChangeFilterAccessor> = []
        prepared.reserveCapacity(changeFilterMasks.count * 2)

        for access in repeat each accessors {
            guard let componentFilter = changeFilterMasks[access.tag] else { continue }
            if !componentFilter.mask.contains(.removed) {
                prepared.append(ChangeFilterAccessor(mask: componentFilter.mask, isOr: componentFilter.isOr, indices: access.indices, ticks: access.ticks))
                remaining.remove(access.tag)
            } else if componentFilter.isOr {
                // OR filter with mixed present & removed bits: emit separate accessors.
                let presentBits = componentFilter.mask.subtracting(.removed)
                if !presentBits.isEmpty {
                    prepared.append(ChangeFilterAccessor(mask: presentBits, isOr: true, indices: access.indices, ticks: access.ticks))
                }
                if let (removedIndices, removedTicks) = pool.pointee.removedIndices(for: access.tag) {
                    prepared.append(ChangeFilterAccessor(mask: .removed, isOr: true, indices: removedIndices, ticks: removedTicks))
                }
                remaining.remove(access.tag)
            }
        }

        // Slow path for tags not found in the type pack.
        for tag in remaining.tags {
            guard let componentFilter = changeFilterMasks[tag] else { continue }
            if !componentFilter.mask.contains(.removed) {
                pool.pointee.components[tag]?.withIndices { indices, ticks in
                    prepared.append(ChangeFilterAccessor(mask: componentFilter.mask, isOr: componentFilter.isOr, indices: indices, ticks: ticks))
                }
            } else if componentFilter.isOr {
                let presentBits = componentFilter.mask.subtracting(.removed)
                if !presentBits.isEmpty {
                    pool.pointee.components[tag]?.withIndices { indices, ticks in
                        prepared.append(ChangeFilterAccessor(mask: presentBits, isOr: true, indices: indices, ticks: ticks))
                    }
                }
                if let (removedIndices, removedTicks) = pool.pointee.removedIndices(for: tag) {
                    prepared.append(ChangeFilterAccessor(mask: .removed, isOr: true, indices: removedIndices, ticks: removedTicks))
                }
            } else if componentFilter.mask.contains(.removed) {
                if let (removedIndices, removedTicks) = pool.pointee.removedIndices(for: tag) {
                    prepared.append(ChangeFilterAccessor(mask: componentFilter.mask, isOr: false, indices: removedIndices, ticks: removedTicks))
                }
            }
        }

        guard !prepared.isEmpty else {
            return ChangeFilterStrategy.none
        }
        return .fast(prepared)
    }

//    @inlinable @inline(__always)
//    static func passes(
//        slot: SlotIndex,
//        requiredComponents: UnsafeBufferPointer<SlotsSpan<ContiguousArray.Index, SlotIndex>>,
//        excludedComponents: UnsafeBufferPointer<SlotsSpan<ContiguousArray.Index, SlotIndex>>
//    ) -> Bool {
////        for component in requiredComponents where component[slot] == .notFound {
////            // Entity does not have all required components, skip.
////            return false
////        }
////        for component in excludedComponents where component[slot] != .notFound {
////            // Entity has at least one excluded component, skip.
////            return false
////        }
//        let requiredBuffer = requiredComponents.baseAddress.unsafelyUnwrapped
//        for index in Range(uncheckedBounds: (0, requiredComponents.count)) where requiredBuffer[index][slot] == .notFound {
//            return false
//        }
//
//        let excludedBuffer = excludedComponents.baseAddress.unsafelyUnwrapped
//        for index in Range(uncheckedBounds: (0, excludedComponents.count)) where excludedBuffer[index][slot] != .notFound {
//            return false
//        }
//
//        return true
//    }

    @inlinable @inline(__always) @_transparent
    static func passes(
        slot: SlotIndex,
        requiredComponents: UnsafePointer<SlotsSpan<ContiguousArray.Index, SlotIndex>>,
        requiredComponentsCount: Int,
        excludedComponents: UnsafePointer<SlotsSpan<ContiguousArray.Index, SlotIndex>>,
        excludedComponentsCount: Int,
        changeFilters: UnsafePointer<ChangeFilterAccessor>,
        changeFiltersCount: Int,
        addedMask: UInt8,
        changedMask: UInt8,
        removedMask: UInt8,
        lastRun: UInt64,
        thisRun: UInt64,
        generations: UnsafePointer<UInt32>,
        generationsCount: Int
    ) -> PassResult {
        assert(Int(bitPattern: generations) != 0, "Generations pointer is nil in passes().")
        assert(slot.rawValue < generationsCount, "Slot \(slot.rawValue) out of bounds for generations (count \(generationsCount)).")
        for index in Range(uncheckedBounds: (0, requiredComponentsCount)) where requiredComponents[index][slot] == .notFound {
            return .noMatch
        }

        for index in Range(uncheckedBounds: (0, excludedComponentsCount)) where excludedComponents[index][slot] != .notFound {
            return .noMatch
        }

        var changeIndex = 0
        var successfulOr = false
        var hasOr = false
        while changeIndex < changeFiltersCount {
            let accessor = changeFilters[changeIndex]
            let isOr = accessor.isOr
            if isOr, successfulOr {
                changeIndex &+= 1
                continue
            }
            hasOr = hasOr || isOr
            let denseIndex = accessor.indices[slot]
            if denseIndex == .notFound {
                if !isOr {
                    return .noMatch
                }
                // OR: this accessor has no data for the slot; skip.
                changeIndex &+= 1
                continue
            }

            let ticks = accessor.ticks.mutablePointer(at: denseIndex).pointee
            let mask = accessor.mask.rawValue

            // If a mask is "or", then we can continue if it is not present.
            // - At least one "or" must be present.
            // - As soon as one "or" is present, we don't need to check the rest.

            if mask & addedMask != 0 {
                if ticks.isAdded(since: lastRun, upTo: thisRun) {
                    successfulOr = successfulOr || isOr
                } else if !isOr {
                    return .filteredByChanges
                }
            }
            if mask & changedMask != 0 {
                if ticks.isChanged(since: lastRun, upTo: thisRun) {
                    successfulOr = successfulOr || isOr
                } else if !isOr {
                    return .filteredByChanges
                }
            }
            if mask & removedMask != 0 {
                if ticks.isRemoved(since: lastRun, upTo: thisRun), ticks.removedGeneration == generations[slot.rawValue] {
                    successfulOr = successfulOr || isOr
                } else if !isOr {
                    return .filteredByChanges
                }
            }

            changeIndex &+= 1
        }
        if hasOr, !successfulOr {
            return .filteredByChanges
        }
        return .passes
    }

    @inlinable @inline(__always) @_transparent
    static func passesMembership(
        _ slot: SlotIndex,
        otherBuffer: UnsafePointer<SlotsSpan<Int, SlotIndex>>,
        otherCount: Int,
        excludedBuffer: UnsafePointer<SlotsSpan<Int, SlotIndex>>,
        excludedCount: Int
    ) -> Bool {
        assert(otherCount == 0 || Int(bitPattern: otherBuffer) != 0, "otherBuffer is nil with otherCount=\(otherCount) in passesMembership().")
        assert(excludedCount == 0 || Int(bitPattern: excludedBuffer) != 0, "excludedBuffer is nil with excludedCount=\(excludedCount) in passesMembership().")
        for index in Range(uncheckedBounds: (0, otherCount)) where otherBuffer[index][slot] == .notFound {
            return false
        }

        for index in Range(uncheckedBounds: (0, excludedCount)) where excludedBuffer[index][slot] != .notFound {
            return false
        }

        return true
    }

    @inlinable @inline(__always) @_transparent
    static func passesChangeFilters(
        _ slot: SlotIndex,
        buffer: UnsafePointer<ChangeFilterAccessor>,
        bufferCount: Int,
        addedMask: UInt8,
        changedMask: UInt8,
        removedMask: UInt8,
        lastRun: UInt64,
        thisRun: UInt64,
        generations: UnsafePointer<UInt32>
    ) -> Bool {
        var successfulOr = false
        var hasOr = false
        var changeIndex = 0
        while changeIndex < bufferCount {
            let accessor = buffer[changeIndex]
            let isOr = accessor.isOr
            if isOr, successfulOr {
                changeIndex &+= 1
                continue
            }
            hasOr = hasOr || isOr
            let denseIndex = accessor.indices[slot]
            if denseIndex == .notFound {
                if !isOr {
                    return false
                }
                // OR: this accessor has no data for the slot; skip.
                changeIndex &+= 1
                continue
            }

            let ticks = accessor.ticks.mutablePointer(at: denseIndex).pointee
            let mask = accessor.mask.rawValue

            // If a mask is "or", then we can continue if it is not present.
            // - At least one "or" must be present.
            // - As soon as one "or" is present, we don't need to check the rest.

            if mask & addedMask != 0 {
                if ticks.isAdded(since: lastRun, upTo: thisRun) {
                    successfulOr = successfulOr || isOr
                } else if !isOr {
                    // We filter for added components, but this component wasn't added.
                    return false
                }
            }
            if mask & changedMask != 0 {
                if ticks.isChanged(since: lastRun, upTo: thisRun) {
                    successfulOr = successfulOr || isOr
                } else if !isOr {
                    // We filter for changes, but no change occurred.
                    return false
                }
            }
            if mask & removedMask != 0 {
                if ticks.isRemoved(since: lastRun, upTo: thisRun), ticks.removedGeneration == generations[slot.rawValue] {
                    successfulOr = successfulOr || isOr
                } else if !isOr {
                    // We filter for removals, but this component wasn't removed for the current entity generation.
                    return false
                }
            }

            changeIndex &+= 1
        }
        if hasOr, !successfulOr {
            return false
        }
        return true
    }

//    @inlinable @inline(__always)
//    func satisfiesChangeFilters(_ context: QueryContext, entityID: Entity.ID) -> Bool {
//        guard !changeFilterMasks.isEmpty else { return true }
//        guard let snapshot = context.systemTickSnapshot else { return false }
//        for (tag, mask) in changeFilterMasks {
//            guard let ticks = context.coordinator.pool.componentTicks(for: tag, entityID: entityID) else {
//                return false
//            }
//            if mask.contains(.added) && !ticks.isAdded(since: snapshot.lastRun, upTo: snapshot.thisRun) {
//                return false
//            }
//            if mask.contains(.changed) && !ticks.isChanged(since: snapshot.lastRun, upTo: snapshot.thisRun) {
//                return false
//            }
//        }
//        return true
//    }
//
//    @inlinable @inline(__always)
//    func satisfiesChangeFiltersFast(
//        systemTickSnapshot: Coordinator.SystemTickSnapshot?,
//        changeAccessors: ContiguousArray<ChangeFilterAccessor>,
//        entityID: Entity.ID
//    ) -> Bool {
//        guard !changeFilterMasks.isEmpty else { return true }
//        guard let snapshot = systemTickSnapshot else { return false }
//        guard changeAccessors.count == changeFilterMasks.count else { return false }
//
//        let addedMask = ChangeFilterMask.added.rawValue
//        let changedMask = ChangeFilterMask.changed.rawValue
//
//        return changeAccessors.withUnsafeBufferPointer { accessors in
//            var index = 0
//            while index < accessors.count {
//                let accessor = accessors[index]
//                let denseIndex = accessor.indices[entityID.slot]
//                guard denseIndex != .notFound else { return false }
//                let ticksPointer = accessor.ticks.mutablePointer(at: denseIndex)
//                let ticks = ticksPointer.pointee
//                let mask = accessor.mask.rawValue
//                if mask & addedMask != 0 && !ticks.isAdded(since: snapshot.lastRun, upTo: snapshot.thisRun) {
//                    return false
//                }
//                if mask & changedMask != 0 && !ticks.isChanged(since: snapshot.lastRun, upTo: snapshot.thisRun) {
//                    return false
//                }
//                index &+= 1
//            }
//            return true
//        }
//    }
//
//    @inlinable @inline(__always)
//    func entitySatisfiesChangeFilters(
//        _ context: QueryContext,
//        systemTickSnapshot: Coordinator.SystemTickSnapshot?,
//        fastAccessors: ContiguousArray<ChangeFilterAccessor>,
//        entityID: Entity.ID
//    ) -> Bool {
//        guard !changeFilterMasks.isEmpty else { return true }
//        return satisfiesChangeFiltersFast(
//            systemTickSnapshot: systemTickSnapshot,
//            changeAccessors: fastAccessors,
//            entityID: entityID
//        )
//    }

    @inlinable @inline(__always)
    public func perform(_ context: some QueryContextConvertible, _ handler: (repeat (each T).ResolvedType) -> Void) {
        let context = context.queryContext
        var (baseSlots, otherComponents, excludedComponents) = getCachedArrays(context.coordinator)
        let ids = isQueryingOnlyForEntityID ? context.coordinator.indices.liveSlots : []
        defer {
            extendLifetime(ids)
        }
        if baseSlots.isEmpty, isQueryingOnlyForEntityID {
            ids.withUnsafeBufferPointer { buffer in
                baseSlots = ContiguousSpan(view: buffer, count: buffer.count)
            }
        }
        guard !baseSlots.isEmpty else { return }
        // TODO: Use RigidArray or TailAllocated here

        let baseCount = baseSlots.count
        guard baseCount > 0 else { return }
        let basePointer = baseSlots.buffer

        let tickSnapshot = context.systemTickSnapshot
        let indices = context.coordinator.indices.generationView
        withTypedBuffers(&context.coordinator.pool, changeTick: context.coordinator.changeTick) { (accessors: repeat TypedAccess<each T>) in
            guard let strategy = prepareChangeFilterAccessors((repeat each accessors), pool: &context.coordinator.pool) else {
                return
            }

            let indicesPointer = indices.pointer
            let otherCount = otherComponents.count
            let excludedCount = excludedComponents.count

            otherComponents.withUnsafeBufferPointer { otherBuffer in
                excludedComponents.withUnsafeBufferPointer { excludedBuffer in
                    let otherPointer = otherBuffer.baseAddress.unsafelyUnwrapped
                    let excludedPointer = excludedBuffer.baseAddress.unsafelyUnwrapped

                    switch strategy {
                    case .none:
                        @inline(__always) @_transparent
                        func run(_ id: (SlotIndex) -> Entity.ID) {
                            for baseIndex in Range(uncheckedBounds: (0, baseCount)) {
                                let slot = basePointer.advanced(by: baseIndex).pointee

                                guard Self.passesMembership(
                                    slot,
                                    otherBuffer: otherPointer,
                                    otherCount: otherCount,
                                    excludedBuffer: excludedPointer,
                                    excludedCount: excludedCount
                                ) else {
                                    continue
                                }

                                let entityID = id(slot)

                                handler(repeat (each T).makeResolved(access: each accessors, entityID: entityID))
                            }
                        }
                        if isQueryingForEntityID {
                            run {
                                Entity.ID(
                                    slot: $0,
                                    generation: indicesPointer.advanced(by: $0.rawValue).pointee
                                )
                            }
                        } else {
                            run {
                                Entity.ID(slot: $0, generation: 0)
                            }
                        }

                    case .fast(let fastChangeAccessors):
                        let lastRun = tickSnapshot.lastRun
                        let thisRun = tickSnapshot.thisRun
                        let addedMask = ChangeFilterMask.added.rawValue
                        let changedMask = ChangeFilterMask.changed.rawValue
                        let removedMask = ChangeFilterMask.removed.rawValue

                        fastChangeAccessors.withUnsafeBufferPointer { changeBuffer in
                            let changeCount = changeBuffer.count
                            let changePointer = changeBuffer.baseAddress.unsafelyUnwrapped

                            var baseIndex = 0
                            while baseIndex < baseCount {
                                let slot = basePointer.advanced(by: baseIndex).pointee
                                baseIndex &+= 1

                                guard
                                    Self.passesMembership(
                                        slot,
                                        otherBuffer: otherPointer,
                                        otherCount: otherCount,
                                        excludedBuffer: excludedPointer,
                                        excludedCount: excludedCount
                                    ),
                                    Self.passesChangeFilters(
                                        slot,
                                        buffer: changePointer,
                                        bufferCount: changeCount,
                                        addedMask: addedMask,
                                        changedMask: changedMask,
                                        removedMask: removedMask,
                                        lastRun: lastRun,
                                        thisRun: thisRun,
                                        generations: indicesPointer
                                    )
                                else {
                                    continue
                                }

                                let entityID = Entity.ID(
                                    slot: slot,
                                    generation: isQueryingForEntityID ? indicesPointer.advanced(by: slot.rawValue).pointee : 0
                                )

                                handler(repeat (each T).makeResolved(access: each accessors, entityID: entityID))
                            }
                        }
                    }
                }
            }
        }
    }
}

extension Query {
//    @inlinable @inline(__always)
//    public func performPreloaded(_ context: some QueryContextConvertible, _ handler: (repeat (each T).ResolvedType) -> Void) {
//        let context = context.queryContext
//        let slots = getCachedPreFilteredSlots(context.coordinator) // TODO: Allow custom order.
//        let tickSnapshot = context.systemTickSnapshot
//        withUnsafePointer(to: context.coordinator.indices) { indices in
//            withTypedBuffers(&context.coordinator.pool, changeTick: context.coordinator.changeTick) { (accessors: repeat TypedAccess<each T>) in
//                let fastChangeAccessors = changeFilterMasks.isEmpty
//                    ? nil
//                    : prepareChangeFilterAccessors((repeat each accessors))
//                for slot in slots {
//                    let generation = indices.pointee[generationFor: slot]
//                    let fullID = Entity.ID(
//                        slot: SlotIndex(rawValue: slot.rawValue),
//                        generation: generation
//                    )
//                    guard entitySatisfiesChangeFilters(
//                        context,
//                        systemTickSnapshot: tickSnapshot,
//                        fastAccessors: fastChangeAccessors,
//                        entityID: fullID
//                    ) else { continue }
//                    let entityID = isQueryingForEntityID ? fullID : Entity.ID(
//                        slot: SlotIndex(rawValue: slot.rawValue),
//                        generation: 0
//                    )
//                    handler(repeat (each T).makeResolved(access: each accessors, entityID: entityID))
//                }
//            }
//        }
//    }

    @inlinable @inline(__always)
    public func performGroup(_ context: some QueryContextConvertible, requireGroup: Bool = false, _ handler: (repeat (each T).ResolvedType) -> Void) {
        let context = context.queryContext
        let tickSnapshot = context.systemTickSnapshot
        
        // Prefer a best-fitting group if available; otherwise fall back to cached slots.
        let best = context.coordinator.bestGroup(for: querySignature)
        let slotsSlice: ContiguousSpan<SlotIndex>
        let exactGroupMatch: Bool
        let owned: ComponentSignature

        if let best {
            slotsSlice = best.slots
            exactGroupMatch = best.exact
            owned = best.owned
        } else if !requireGroup {
            // No group found for query, fall back to precomputed slots.
            print("No group found for query. Consider adding a group matching this query.")
            return perform(context, handler)
        } else {
            print("No group found for query. Consider adding a group matching this query.")
            return
        }
        guard !slotsSlice.isEmpty else { return }

        if exactGroupMatch {
            let indices = context.coordinator.indices.generationView
            withTypedBuffers(&context.coordinator.pool, changeTick: context.coordinator.changeTick) { (accessors: repeat TypedAccess<each T>) in
                guard let strategy = prepareChangeFilterAccessors((repeat each accessors), pool: &context.coordinator.pool) else { return }
                
                switch strategy {
                case .none:
                    // Enumerate dense indices directly: 0..<size aligned across all owned storages
                    for (denseIndex, slot) in slotsSlice.enumerated() {
                        let entityID = Entity.ID(
                            slot: SlotIndex(rawValue: slot.rawValue),
                            generation: isQueryingForEntityID ? indices[slot] : 0
                        )
                        handler(repeat (each T).makeResolvedDense(access: each accessors, denseIndex: denseIndex, entityID: entityID))
                    }

                case .fast(let changeFilters):
                    changeFilters.withUnsafeBufferPointer { changeBuffer in
                        let changePointer = changeBuffer.baseAddress.unsafelyUnwrapped
                        let changeCount = changeBuffer.count
                        let lastRun = tickSnapshot.lastRun
                        let thisRun = tickSnapshot.thisRun
                        let addedMask = ChangeFilterMask.added.rawValue
                        let changedMask = ChangeFilterMask.changed.rawValue
                        let removedMask = ChangeFilterMask.removed.rawValue

                        // Enumerate dense indices directly: 0..<size aligned across all owned storages
                        for (denseIndex, slot) in slotsSlice.enumerated() where Self.passesChangeFilters(
                            slot,
                            buffer: changePointer,
                            bufferCount: changeCount,
                            addedMask: addedMask,
                            changedMask: changedMask,
                            removedMask: removedMask,
                            lastRun: lastRun,
                            thisRun: thisRun,
                            generations: indices.pointer
                        ) {
                            let entityID = Entity.ID(
                                slot: SlotIndex(rawValue: slot.rawValue),
                                generation: isQueryingForEntityID ? indices[slot] : 0
                            )
                            handler(repeat (each T).makeResolvedDense(access: each accessors, denseIndex: denseIndex, entityID: entityID))
                        }
                    }
                }
            }
        } else {
            let indices = context.coordinator.indices.generationView
            let signatures = context.coordinator.entitySignaturesView
            let querySignature = self.signature
            withTypedBuffers(&context.coordinator.pool, changeTick: context.coordinator.changeTick) { (accessors: repeat TypedAccess<each T>) in
                @inline(__always)
                func resolve<C: Component>(_ type: C.Type, access: TypedAccess<C>, denseIndex: Int, entityID: Entity.ID, owned: ComponentSignature) -> C.ResolvedType {
                    if owned.contains(C.componentTag) { // TODO: Does this `if` actually help with performance?
                        type.makeResolvedDense(access: access, denseIndex: denseIndex, entityID: entityID)
                    } else {
                        type.makeResolved(access: access, entityID: entityID)
                    }
                }
                
                guard let strategy = prepareChangeFilterAccessors((repeat each accessors), pool: &context.coordinator.pool) else { return }
                switch strategy {
                case .none:
                    // Enumerate dense indices directly: 0..<size aligned across all owned storages
                    for (denseIndex, slot) in slotsSlice.enumerated() {
                        let signature = signatures[slot]
                        
                        guard
                            signature.rawHashValue.isSuperset(
                                of: querySignature.rawHashValue,
                                isDisjoint: excludedSignature.rawHashValue
                            )
                        else {
                            continue
                        }
                        
                        let entityID = Entity.ID(
                            slot: SlotIndex(rawValue: slot.rawValue),
                            generation: isQueryingForEntityID ? indices[slot] : 0
                        )
                        
                        handler(repeat resolve((each T).self, access: each accessors, denseIndex: denseIndex, entityID: entityID, owned: owned))
                    }
                    
                case .fast(let changeFilters):
                    changeFilters.withUnsafeBufferPointer { changeBuffer in
                        let changePointer = changeBuffer.baseAddress.unsafelyUnwrapped
                        let changeCount = changeBuffer.count
                        let lastRun = tickSnapshot.lastRun
                        let thisRun = tickSnapshot.thisRun
                        let addedMask = ChangeFilterMask.added.rawValue
                        let changedMask = ChangeFilterMask.changed.rawValue
                        let removedMask = ChangeFilterMask.removed.rawValue

                        // Enumerate dense indices directly: 0..<size aligned across all owned storages
                        for (denseIndex, slot) in slotsSlice.enumerated() where Self.passesChangeFilters(
                            slot,
                            buffer: changePointer,
                            bufferCount: changeCount,
                            addedMask: addedMask,
                            changedMask: changedMask,
                            removedMask: removedMask,
                            lastRun: lastRun,
                            thisRun: thisRun,
                            generations: indices.pointer
                        ) {
                            let signature = signatures[slot]
                            
                            guard
                                signature.rawHashValue.isSuperset(
                                    of: querySignature.rawHashValue,
                                    isDisjoint: excludedSignature.rawHashValue
                                )
                            else {
                                continue
                            }
                            
                            let entityID = Entity.ID(
                                slot: SlotIndex(rawValue: slot.rawValue),
                                generation: isQueryingForEntityID ? indices[slot] : 0
                            )
                            
                            handler(repeat resolve((each T).self, access: each accessors, denseIndex: denseIndex, entityID: entityID, owned: owned))
                        }
                    }
                }
            }
        }
    }
}

extension Query {
    @inlinable @inline(__always)
    public static func emptyEntities(_ context: some QueryContextConvertible) -> [Entity.ID] {
        context
            .queryContext
            .coordinator
            .entitySignatures
            .lazy
            .enumerated()
            .filter {
                $1.isEmpty
            }
            .map {
                let slot = SlotIndex(rawValue: $0.offset)
                return Entity.ID(slot: slot, generation: context.queryContext.coordinator.indices[generationFor: slot])
            }
    }
}

extension Query {
    @inlinable @inline(__always)
    public func unsafeFetchAllWritable(_ context: some QueryContextConvertible) -> LazyWritableQuerySequence<repeat each T> {
        let context = context.queryContext
        var (baseSlots, otherComponents, excludedComponents) = getCachedArrays(context.coordinator)
        let ids = isQueryingOnlyForEntityID ? context.coordinator.indices.liveSlots : []
        defer {
            extendLifetime(ids)
        }
        if baseSlots.isEmpty, isQueryingOnlyForEntityID {
            ids.withUnsafeBufferPointer { buffer in
                baseSlots = ContiguousSpan(view: buffer, count: buffer.count)
            }
        }
        guard !baseSlots.isEmpty else { return LazyWritableQuerySequence() }
        let tickSnapshot = context.systemTickSnapshot

        let accessors = withTypedBuffers(&context.coordinator.pool, changeTick: context.coordinator.changeTick) { (accessors: repeat TypedAccess<each T>) in
            (repeat each accessors)
        }

        let entities: [Entity.ID] = context.coordinator.indices.generation.withUnsafeBufferPointer { generationsBuffer in
            let generationsPointer = generationsBuffer.baseAddress.unsafelyUnwrapped
            assert(generationsBuffer.count > 0 || baseSlots.count == 0, "Generation buffer is empty but baseSlots has \(baseSlots.count) slots.")
            return otherComponents.withUnsafeBufferPointer { otherBuffer in
                excludedComponents.withUnsafeBufferPointer { excludedBuffer in
                    let otherPointer = otherBuffer.baseAddress.unsafelyUnwrapped
                    let otherCount = otherBuffer.count
                    let excludedPointer = excludedBuffer.baseAddress.unsafelyUnwrapped
                    let excludedCount = excludedBuffer.count
                    guard let strategy = prepareChangeFilterAccessors((repeat each accessors), pool: &context.coordinator.pool) else {
                        return []
                    }
                    var entities: [Entity.ID] = []
                    entities.reserveCapacity(baseSlots.count)
                    switch strategy {
                    case .none:
                        for slot in baseSlots where Self.passesMembership(
                            slot,
                            otherBuffer: otherPointer,
                            otherCount: otherCount,
                            excludedBuffer: excludedPointer,
                            excludedCount: excludedCount
                        ) {
                            let entityID = Entity.ID(slot: slot, generation: isQueryingForEntityID ? generationsPointer[slot.rawValue] : 0)
                            entities.append(entityID)
                        }
                        return entities

                    case .fast(let changeFilters):
                        return changeFilters.withUnsafeBufferPointer { changeBuffer in
                            let changePointer = changeBuffer.baseAddress.unsafelyUnwrapped
                            let changeCount = changeBuffer.count
                            let lastRun = tickSnapshot.lastRun
                            let thisRun = tickSnapshot.thisRun
                            let addedMask = ChangeFilterMask.added.rawValue
                            let changedMask = ChangeFilterMask.changed.rawValue
                            let removedMask = ChangeFilterMask.removed.rawValue
                            for slot in baseSlots {
                                guard Self.passes(
                                    slot: slot,
                                    requiredComponents: otherPointer,
                                    requiredComponentsCount: otherCount,
                                    excludedComponents: excludedPointer,
                                    excludedComponentsCount: excludedCount,
                                    changeFilters: changePointer,
                                    changeFiltersCount: changeCount,
                                    addedMask: addedMask,
                                    changedMask: changedMask,
                                    removedMask: removedMask,
                                    lastRun: lastRun,
                                    thisRun: thisRun,
                                    generations: generationsPointer,
                                    generationsCount: generationsBuffer.count
                                ) == .passes else {
                                    continue
                                }
                                let entityID = Entity.ID(slot: slot, generation: isQueryingForEntityID ? generationsPointer[slot.rawValue] : 0)
                                entities.append(entityID)
                            }

                            return entities
                        }
                    }
                }
            }
        }

        return LazyWritableQuerySequence(
            entityIDs: entities,
            accessors: repeat each accessors
        )
    }
}
