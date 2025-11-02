import Foundation

public struct Query<each T: Component> where repeat each T: ComponentResolving {
    /// All components which entities are required to have but will not be included in the query output.
    @inline(__always)
    public let backstageComponents: Set<ComponentTag> // Or witnessComponents?

    /// Components that must have been added since the system last ran.
    @inline(__always)
    public let addedComponents: Set<ComponentTag>

    /// Components that must have changed since the system last ran.
    @inline(__always)
    public let changedComponents: Set<ComponentTag>

    /// All components where this query ignores contained entities.
    @inline(__always)
    public let excludedComponents: Set<ComponentTag>

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

    @inline(__always)
    let hash: QueryHash

    @usableFromInline
    let isQueryingForEntityID: Bool

    @usableFromInline
    init(
        backstageComponents: Set<ComponentTag>,
        excludedComponents: Set<ComponentTag>,
        addedComponents: Set<ComponentTag>,
        changedComponents: Set<ComponentTag>,
        isQueryingForEntityID: Bool
    ) {
        self.backstageComponents = backstageComponents
        self.backstageSignature = ComponentSignature(backstageComponents)
        self.excludedComponents = excludedComponents
        self.addedComponents = addedComponents
        self.changedComponents = changedComponents
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
    }

    @inlinable @inline(__always)
    public func appending<U>(_ type: U.Type = U.self) -> Query<repeat each T, U> {
        Query<repeat each T, U>(
            backstageComponents: backstageComponents,
            excludedComponents: excludedComponents,
            addedComponents: addedComponents,
            changedComponents: changedComponents,
            isQueryingForEntityID: isQueryingForEntityID || U.self is WithEntityID.Type
        )
    }

    @inlinable @inline(__always)
    public func callAsFunction(_ context: QueryContext, _ handler: (repeat (each T).ResolvedType) -> Void) {
        perform(context, handler)
    }

    @inlinable @inline(__always)
    public func callAsFunction(_ coordinator: Coordinator, _ handler: (repeat (each T).ResolvedType) -> Void) {
        perform(QueryContext(coordinator: coordinator), handler)
    }

    @inlinable @inline(__always)
    public func callAsFunction(preloaded context: QueryContext, _ handler: (repeat (each T).ResolvedType) -> Void) {
        performPreloaded(context, handler)
    }

    @inlinable @inline(__always)
    public func callAsFunction(preloaded coordinator: Coordinator, _ handler: (repeat (each T).ResolvedType) -> Void) {
        performPreloaded(QueryContext(coordinator: coordinator), handler)
    }

    @inlinable @inline(__always)
    public func callAsFunction(parallel context: QueryContext, _ handler: @Sendable (repeat (each T).ResolvedType) -> Void) where repeat each T: Sendable {
        performParallel(context, handler)
    }

    @inlinable @inline(__always)
    public func callAsFunction(parallel coordinator: Coordinator, _ handler: @Sendable (repeat (each T).ResolvedType) -> Void) where repeat each T: Sendable {
        performParallel(QueryContext(coordinator: coordinator), handler)
    }

    @inlinable @inline(__always)
    public func callAsFunction(preloadedParallel context: QueryContext, _ handler: @Sendable (repeat (each T).ResolvedType) -> Void) where repeat each T: Sendable {
        performPreloadedParallel(context, handler)
    }

    @inlinable @inline(__always)
    public func callAsFunction(preloadedParallel coordinator: Coordinator, _ handler: @Sendable (repeat (each T).ResolvedType) -> Void) where repeat each T: Sendable {
        performPreloadedParallel(QueryContext(coordinator: coordinator), handler)
    }

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
        let context = context.queryContext
        let (baseSlots, otherComponents, excludedComponents) = getCachedArrays(context.coordinator)

        return withTypedBuffers(context.coordinator, &context.coordinator.pool) { (accessors: repeat TypedAccess<each T>) in
            for slot in baseSlots where passes(
                slot: slot,
                otherComponents: otherComponents,
                excludedComponents: excludedComponents,
                context: context
            ) {
                return (
                    repeat (each T).makeReadOnlyResolved(
                        access: each accessors,
                        entityID: Entity.ID(slot: slot, generation: context.coordinator.indices[generationFor: slot])
                    )
                )
            }
            return nil
        }
    }
}

extension Query {
    @inlinable @inline(__always)
    public func fetchAll(_ context: some QueryContextConvertible) -> LazyQuerySequence<repeat each T> {
        let context = context.queryContext
        let slots = getCachedPreFilteredSlots(context.coordinator)

        let accessors = withTypedBuffers(context.coordinator, &context.coordinator.pool) { (accessors: repeat TypedAccess<each T>) in
            (repeat each accessors)
        }
        var entityIDs: [Entity.ID] = []
        entityIDs.reserveCapacity(slots.count)
        for slot in slots where passesChangeFilters(slot: slot, context: context) {
            let generation = isQueryingForEntityID ? context.coordinator.indices[generationFor: slot] : 0
            entityIDs.append(Entity.ID(slot: slot, generation: generation))
        }

        return LazyQuerySequence(
            entityIDs: entityIDs,
            accessors: repeat each accessors
        )
    }
}

extension Query {
    @inlinable @inline(__always)
    public func performPreloadedParallel(_ context: some QueryContextConvertible, _ handler: @Sendable (repeat (each T).ResolvedType) -> Void) where repeat each T: Sendable {
        let context = context.queryContext
        let slots = getCachedPreFilteredSlots(context.coordinator)
        withTypedBuffers(context.coordinator, &context.coordinator.pool) { (accessors: repeat TypedAccess<each T>) in
            let cores = ProcessInfo.processInfo.processorCount
            let chunkSize = max(1, (slots.count + cores - 1) / cores) // ceil division
            let chunks = (slots.count + chunkSize - 1) / chunkSize // ceil number of chunks

            withUnsafePointer(to: &context.coordinator.indices) {
                nonisolated(unsafe) let indices: UnsafePointer<IndexRegistry> = $0
                DispatchQueue.concurrentPerform(iterations: chunks) { i in
                    let start = i * chunkSize
                    let end = min(start + chunkSize, slots.count)
                    if start >= end { return } // guard against empty/invalid slice

                    for slot in slots[start..<end] {
                        guard passesChangeFilters(slot: slot, context: context) else { continue }
                        handler(repeat (each T).makeResolved(
                            access: each accessors,
                            entityID: Entity.ID(slot: slot, generation: indices.pointee[generationFor: slot])
                        ))
                    }
                }
            }
        }
    }
}

extension Query {
    @inlinable @inline(__always)
    public func performParallel(_ context: some QueryContextConvertible, _ handler: @Sendable (repeat (each T).ResolvedType) -> Void) where repeat each T: Sendable {
        let context = context.queryContext
        let slots = getCachedBaseSlots(context.coordinator)
        withTypedBuffers(context.coordinator, &context.coordinator.pool) { (accessors: repeat TypedAccess<each T>) in
            let querySignature = self.signature
            let excludedSignature = self.excludedSignature
            let cores = ProcessInfo.processInfo.processorCount
            let chunkSize = max(1, (slots.count + cores - 1) / cores) // ceil division
            let chunks = (slots.count + chunkSize - 1) / chunkSize // ceil number of chunks

            withUnsafePointer(to: &context.coordinator.indices) {
                nonisolated(unsafe) let indices: UnsafePointer<IndexRegistry> = $0
                DispatchQueue.concurrentPerform(iterations: chunks) { i in
                    let start = i * chunkSize
                    let end = min(start + chunkSize, slots.count)
                    if start >= end { return } // guard against empty/invalid slice

                    for slot in slots[start..<end] {
                        let slotRaw = slot.rawValue
                        let signature = context.coordinator.entitySignatures[slotRaw]
                        guard
                            signature.rawHashValue.isSuperset(
                                of: querySignature.rawHashValue,
                                isDisjoint: excludedSignature.rawHashValue
                            )
                        else {
                            continue
                        }
                        guard passesChangeFilters(slot: slot, context: context) else {
                            continue
                        }
                        handler(repeat (each T).makeResolved(
                            access: each accessors,
                            entityID: Entity.ID(slot: slot, generation: isQueryingForEntityID ? indices.pointee[generationFor: slot] : 0)
                        ))
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
        let baseSlots = getCachedBaseSlots(context.coordinator)
        withTypedBuffers(context.coordinator, &context.coordinator.pool) { (accessors: repeat TypedAccess<each T>) in
            let querySignature = self.signature
            let excludedSignature = self.excludedSignature

            slotLoop: for slot in baseSlots {
                let slotRaw = slot.rawValue
                let signature = context.coordinator.entitySignatures[slotRaw]

                guard
                    signature.rawHashValue.isSuperset(
                        of: querySignature.rawHashValue,
                        isDisjoint: excludedSignature.rawHashValue
                    )
                else {
                    continue slotLoop
                }

                guard passesChangeFilters(slot: slot, context: context) else {
                    continue slotLoop
                }

                let id = Entity.ID(
                    slot: SlotIndex(rawValue: slotRaw),
                    generation: context.coordinator.indices[generationFor: slot]
                )
                handler(repeat (each T).makeResolved(access: each accessors, entityID: id))
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
        let filteredSlots = getCachedPreFilteredSlots(context.coordinator)
        withTypedBuffers(context.coordinator, &context.coordinator.pool) { (accessors: repeat TypedAccess<each T>) in
            let resolved = filteredSlots.compactMap { [indices = context.coordinator.indices] slot -> CombinationPack<repeat (each T).ResolvedType>? in
                guard passesChangeFilters(slot: slot, context: context) else { return nil }
                let id = Entity.ID(
                    slot: slot,
                    generation: isQueryingForEntityID ? indices[generationFor: slot] : 0
                )

                return CombinationPack((repeat (each T).makeResolved(access: each accessors, entityID: id)))
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

extension Query {
    @inlinable @inline(__always)
    func passes(
        slot: SlotIndex,
        otherComponents: [SlotsSpan<ContiguousArray.Index, SlotIndex>],
        excludedComponents: [SlotsSpan<ContiguousArray.Index, SlotIndex>],
        context: QueryContext
    ) -> Bool {
        for component in otherComponents where component[slot] == .notFound {
            // Entity does not have all required components, skip.
            return false
        }
        for component in excludedComponents where component[slot] != .notFound {
            // Entity has at least one excluded component, skip.
            return false
        }

        return passesChangeFilters(slot: slot, context: context)
    }

    @inlinable @inline(__always)
    func passesChangeFilters(slot: SlotIndex, context: QueryContext) -> Bool {
        if addedComponents.isEmpty && changedComponents.isEmpty {
            return true
        }

        let currentTick = context.coordinator.currentChangeTick()
        let lastTick = clampTickAge(context.lastRunTick, relativeTo: currentTick)

        if !addedComponents.isEmpty {
            for tag in addedComponents {
                let addedTick = context.coordinator.lastAddedTick(for: tag, slot: slot)
                if !isTickNewer(addedTick, than: lastTick, relativeTo: currentTick) {
                    return false
                }
            }
        }

        if !changedComponents.isEmpty {
            for tag in changedComponents {
                let changedTick = context.coordinator.lastChangedTick(for: tag, slot: slot)
                if !isTickNewer(changedTick, than: lastTick, relativeTo: currentTick) {
                    return false
                }
            }
        }

        return true
    }

    @inlinable @inline(__always)
    public func perform(_ context: some QueryContextConvertible, _ handler: (repeat (each T).ResolvedType) -> Void) {
        let context = context.queryContext
        let (baseSlots, otherComponents, excludedComponents) = getCachedArrays(context.coordinator)
        // TODO: Use RigidArray or TailAllocated here

        withUnsafePointer(to: context.coordinator.indices) { indices in
            withTypedBuffers(context.coordinator, &context.coordinator.pool) { (accessors: repeat TypedAccess<each T>) in
                @_transparent
                func withGeneration() {
                    for slot in baseSlots where passes(
                        slot: slot,
                        otherComponents: otherComponents,
                        excludedComponents: excludedComponents,
                        context: context
                    ) {
                        let id = Entity.ID(
                            slot: SlotIndex(rawValue: slot.rawValue),
                            generation: indices.pointee[generationFor: slot]
                        )
                        handler(repeat (each T).makeResolved(access: each accessors, entityID: id))
                    }
                }
                @_transparent
                func withoutGeneration() {
                    for slot in baseSlots where passes(
                        slot: slot,
                        otherComponents: otherComponents,
                        excludedComponents: excludedComponents,
                        context: context
                    ) {
                        let id = Entity.ID(
                            slot: SlotIndex(rawValue: slot.rawValue),
                            generation: 0
                        )
                        handler(repeat (each T).makeResolved(access: each accessors, entityID: id))
                    }
                }
                if isQueryingForEntityID {
                    withGeneration()
                } else {
                    withoutGeneration()
                }
            }
        }
    }
}

extension Query {
    @inlinable @inline(__always)
    public func performPreloaded(_ context: some QueryContextConvertible, _ handler: (repeat (each T).ResolvedType) -> Void) {
        let context = context.queryContext
        let slots = getCachedPreFilteredSlots(context.coordinator) // TODO: Allow custom order.
        withUnsafePointer(to: context.coordinator.indices) { indices in
            withTypedBuffers(context.coordinator, &context.coordinator.pool) { (accessors: repeat TypedAccess<each T>) in
                for slot in slots where passesChangeFilters(slot: slot, context: context) {
                    let id = Entity.ID(
                        slot: SlotIndex(rawValue: slot.rawValue),
                        generation: isQueryingForEntityID ? indices.pointee[generationFor: slot] : 0
                    )
                    handler(repeat (each T).makeResolved(access: each accessors, entityID: id))
                }
            }
        }
    }

    @inlinable @inline(__always)
    public func performGroup(_ context: some QueryContextConvertible, requireGroup: Bool = false, _ handler: (repeat (each T).ResolvedType) -> Void) {
        let context = context.queryContext

        // Prefer a best-fitting group if available; otherwise fall back to cached slots.
        let best = context.coordinator.bestGroup(for: querySignature)
        let slotsSlice: ArraySlice<SlotIndex>
        let exactGroupMatch: Bool
        let owned: ComponentSignature
        if let best {
            slotsSlice = best.slots
            exactGroupMatch = best.exact
            owned = best.owned
        } else if !requireGroup {
            // No group found for query, fall back to precomputed slots.
            slotsSlice = context.coordinator.pool.slots(
                repeat (each T).self,
                included: backstageComponents,
                excluded: excludedComponents
            )[...]
            exactGroupMatch = false
            owned = ComponentSignature()
            print("No group found for query, falling back to precomputed slots. Consider adding a group matching this query.")
        } else {
            slotsSlice = []
            exactGroupMatch = false
            owned = ComponentSignature()
            print("No group found for query. Consider adding a group matching this query.")
        }

        if exactGroupMatch {
            withUnsafePointer(to: context.coordinator.indices) { indices in
                withTypedBuffers(context.coordinator, &context.coordinator.pool) { (accessors: repeat TypedAccess<each T>) in
                    // Enumerate dense indices directly: 0..<size aligned across all owned storages
                    for (denseIndex, slot) in slotsSlice.enumerated() {
                        guard passesChangeFilters(slot: slot, context: context) else { continue }
                        let id = Entity.ID(
                            slot: SlotIndex(rawValue: slot.rawValue),
                            generation: isQueryingForEntityID ? indices.pointee[generationFor: slot] : 0
                        )
                        handler(repeat (each T).makeResolvedDense(access: each accessors, denseIndex: denseIndex, entityID: id))
                    }
                }
            }
        } else {
            let querySignature = self.signature
            let excludedSignature = self.excludedSignature
            withUnsafePointer(to: context.coordinator.indices) { indices in
                withTypedBuffers(context.coordinator, &context.coordinator.pool) { (accessors: repeat TypedAccess<each T>) in
                    // Enumerate dense indices directly: 0..<size aligned across all owned storages
                    for (denseIndex, slot) in slotsSlice.enumerated() {
                        // Skip entities that don't satisfy the query when reusing a non-exact group (future use).
                        // TODO: Optional components are ignored.
                        let entitySignature = context.coordinator.entitySignatures[slot.index]
                        guard entitySignature.isSuperset(of: querySignature, isDisjoint: excludedSignature) else {
                            continue
                        }
                        guard passesChangeFilters(slot: slot, context: context) else {
                            continue
                        }
                        let id = Entity.ID(
                            slot: SlotIndex(rawValue: slot.rawValue),
                            generation: isQueryingForEntityID ? indices.pointee[generationFor: slot] : 0
                        )

                        @inline(__always)
                        func resolve<C: Component>(_ type: C.Type, access: TypedAccess<C>, denseIndex: Int, entityID: Entity.ID, owned: ComponentSignature) -> C.ResolvedType {
                            if owned.contains(C.componentTag) { // TODO: Does this `if` actually help with performance?
                                type.makeResolvedDense(access: access, denseIndex: denseIndex, entityID: entityID)
                            } else {
                                type.makeResolved(access: access, entityID: entityID)
                            }
                        }
                        handler(repeat resolve((each T).self, access: each accessors, denseIndex: denseIndex, entityID: id, owned: owned))
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
        let slots = getCachedPreFilteredSlots(context.coordinator)

        let accessors = withTypedBuffers(context.coordinator, &context.coordinator.pool) { (accessors: repeat TypedAccess<each T>) in
            (repeat each accessors)
        }
        var entityIDs: [Entity.ID] = []
        entityIDs.reserveCapacity(slots.count)
        for slot in slots where passesChangeFilters(slot: slot, context: context) {
            let generation = isQueryingForEntityID ? context.coordinator.indices[generationFor: slot] : 0
            entityIDs.append(Entity.ID(slot: slot, generation: generation))
        }

        return LazyWritableQuerySequence(
            entityIDs: entityIDs,
            accessors: repeat each accessors
        )
    }
}
