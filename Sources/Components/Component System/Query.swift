import Foundation

public struct ChangeFilter: Hashable, Sendable {
    public enum Kind: Hashable, Sendable {
        case added
        case changed
    }

    @usableFromInline
    let tag: ComponentTag
    @usableFromInline
    let kind: Kind

    @usableFromInline
    init(tag: ComponentTag, kind: Kind) {
        self.tag = tag
        self.kind = kind
    }
}

public struct Query<each T: Component> where repeat each T: ComponentResolving {
    /// All components which entities are required to have but will not be included in the query output.
    @inline(__always)
    public let backstageComponents: Set<ComponentTag> // Or witnessComponents?

    /// All components where this query ignores contained entities.
    @inline(__always)
    public let excludedComponents: Set<ComponentTag>

    /// Change filters applied to this query.
    @inline(__always)
    public let changeFilters: Set<ChangeFilter>

    @usableFromInline
    let changeFilterMasks: [ComponentTag: ChangeFilterMask]

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
        let tickSnapshot = context.systemTickSnapshot

        return withTypedBuffers(&context.coordinator.pool, changeTick: context.coordinator.changeTick) { (accessors: repeat TypedAccess<each T>) in
//            let fastChangeAccessors = changeFilterMasks.isEmpty
//                ? nil
//                : prepareChangeFilterAccessors((repeat each accessors))
//            for slot in baseSlots where Self.passes(
//                slot: slot,
//                otherComponents: otherComponents,
//                excludedComponents: excludedComponents
//            ) {
//                let fullID = Entity.ID(slot: slot, generation: context.coordinator.indices[generationFor: slot])
//                guard entitySatisfiesChangeFilters(
//                    context,
//                    systemTickSnapshot: tickSnapshot,
//                    fastAccessors: fastChangeAccessors,
//                    entityID: fullID
//                ) else { continue }
//                let entityID = isQueryingForEntityID ? fullID : Entity.ID(slot: slot, generation: 0)
//                return (
//                    repeat (each T).makeReadOnlyResolved(
//                        access: each accessors,
//                        entityID: entityID
//                    )
//                )
//            }
            return nil
        }
    }
}

extension Query {
    @inlinable @inline(__always)
    public func fetchAll(_ context: some QueryContextConvertible) -> LazyQuerySequence<repeat each T> {
//        let context = context.queryContext
//        let slots = getCachedPreFilteredSlots(context.coordinator)
//
//        let accessors = withTypedBuffers(&context.coordinator.pool, changeTick: context.coordinator.changeTick) { (accessors: repeat TypedAccess<each T>) in
//            (repeat each accessors)
//        }
//        var entityIDs: [Entity.ID] = []
//        entityIDs.reserveCapacity(slots.count)
//        for slot in slots {
//            let fullID = Entity.ID(slot: slot, generation: context.coordinator.indices[generationFor: slot])
//            guard satisfiesChangeFilters(context, entityID: fullID) else { continue }
//            let entityID = isQueryingForEntityID ? fullID : Entity.ID(slot: slot, generation: 0)
//            entityIDs.append(entityID)
//        }
//
//        return LazyQuerySequence(
//            entityIDs: entityIDs,
//            accessors: repeat each accessors
//        )
        return LazyQuerySequence()
    }
}

extension Query {
    @inlinable @inline(__always)
    public func performPreloadedParallel(_ context: some QueryContextConvertible, _ handler: @Sendable (repeat (each T).ResolvedType) -> Void) where repeat each T: Sendable {
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
    }
}

extension Query {
    @inlinable @inline(__always)
    public func performParallel(_ context: some QueryContextConvertible, _ handler: @Sendable (repeat (each T).ResolvedType) -> Void) where repeat each T: Sendable {
        let context = context.queryContext
        let slots = getCachedBaseSlots(context.coordinator)
        let tickSnapshot = context.systemTickSnapshot
        withTypedBuffers(&context.coordinator.pool, changeTick: context.coordinator.changeTick) { (accessors: repeat TypedAccess<each T>) in
            let fastChangeAccessors = changeFilterMasks.isEmpty
                ? nil
                : prepareChangeFilterAccessors((repeat each accessors))
            let querySignature = self.signature
            let excludedSignature = self.excludedSignature
            let cores = ProcessInfo.processInfo.processorCount
            let chunkSize = max(1, (slots.count + cores - 1) / cores) // ceil division
            let chunks = (slots.count + chunkSize - 1) / chunkSize // ceil number of chunks

//            withUnsafePointer(to: &context.coordinator.indices) {
//                nonisolated(unsafe) let indices: UnsafePointer<IndexRegistry> = $0
//                DispatchQueue.concurrentPerform(iterations: chunks) { i in
//                    let start = i * chunkSize
//                    let end = min(start + chunkSize, slots.count)
//                    if start >= end { return } // guard against empty/invalid slice
//
//                    for slot in slots[start..<end] {
//                        let slotRaw = slot.rawValue
//                        let signature = context.coordinator.entitySignatures[slotRaw]
//                        guard
//                            signature.rawHashValue.isSuperset(
//                                of: querySignature.rawHashValue,
//                                isDisjoint: excludedSignature.rawHashValue
//                            )
//                        else {
//                            continue
//                        }
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
        }
    }
}

extension Query {
    // This is just here as an example, signatures will be important for archetypes and groups
    @inlinable @inline(__always)
    public func performWithSignature(_ context: some QueryContextConvertible, _ handler: (repeat (each T).ResolvedType) -> Void) {
        let context = context.queryContext
        let baseSlots = getCachedBaseSlots(context.coordinator)
        let tickSnapshot = context.systemTickSnapshot
//        withTypedBuffers(&context.coordinator.pool, changeTick: context.coordinator.changeTick) { (accessors: repeat TypedAccess<each T>) in
//            let fastChangeAccessors = changeFilterMasks.isEmpty
//                ? nil
//                : prepareChangeFilterAccessors((repeat each accessors))
//            let querySignature = self.signature
//            let excludedSignature = self.excludedSignature
//
//            slotLoop: for slot in baseSlots {
//                let slotRaw = slot.rawValue
//                let signature = context.coordinator.entitySignatures[slotRaw]
//
//                guard
//                    signature.rawHashValue.isSuperset(
//                        of: querySignature.rawHashValue,
//                        isDisjoint: excludedSignature.rawHashValue
//                    )
//                else {
//                    continue slotLoop
//                }
//
//                let generation = context.coordinator.indices[generationFor: slot]
//                let fullID = Entity.ID(
//                    slot: SlotIndex(rawValue: slotRaw),
//                    generation: generation
//                )
//                guard entitySatisfiesChangeFilters(
//                    context,
//                    systemTickSnapshot: tickSnapshot,
//                    fastAccessors: fastChangeAccessors,
//                    entityID: fullID
//                ) else { continue }
//                let entityID = isQueryingForEntityID ? fullID : Entity.ID(
//                    slot: SlotIndex(rawValue: slotRaw),
//                    generation: 0
//                )
//                handler(repeat (each T).makeResolved(access: each accessors, entityID: entityID))
//            }
//        }
    }
}

extension Query {
    @inlinable @inline(__always)
    public func performCombinations(
        _ context: some QueryContextConvertible,
        _ handler: (CombinationPack<repeat (each T).ResolvedType>, CombinationPack<repeat (each T).ResolvedType>) -> Void
    ) {
//        let context = context.queryContext
//        let filteredSlots = getCachedPreFilteredSlots(context.coordinator)
//        let tickSnapshot = context.systemTickSnapshot
//        withTypedBuffers(&context.coordinator.pool, changeTick: context.coordinator.changeTick) { (accessors: repeat TypedAccess<each T>) in
//            let fastChangeAccessors = changeFilterMasks.isEmpty
//                ? nil
//                : prepareChangeFilterAccessors((repeat each accessors))
//            let indices = context.coordinator.indices
//            var resolved: [CombinationPack<repeat (each T).ResolvedType>] = []
//            resolved.reserveCapacity(filteredSlots.count)
//            for slot in filteredSlots {
//                let generation = indices[generationFor: slot]
//                let fullID = Entity.ID(slot: slot, generation: generation)
//                guard entitySatisfiesChangeFilters(
//                    context,
//                    systemTickSnapshot: tickSnapshot,
//                    fastAccessors: fastChangeAccessors,
//                    entityID: fullID
//                ) else { continue }
//                let entityID = isQueryingForEntityID ? fullID : Entity.ID(slot: slot, generation: 0)
//                let pack = CombinationPack((repeat (each T).makeResolved(access: each accessors, entityID: entityID)))
//                resolved.append(pack)
//            }
//            for i in 0..<resolved.count {
//                for j in i+1..<resolved.count {
//                    handler(
//                        resolved[i],
//                        resolved[j]
//                    )
//                }
//            }
//        }
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
    static let added = ChangeFilterMask(rawValue: 1 << 0)

    @usableFromInline
    static let changed = ChangeFilterMask(rawValue: 1 << 1)
}

@usableFromInline
struct ChangeFilterAccessor {
    @usableFromInline
    let mask: ChangeFilterMask
    @usableFromInline
    let indices: SlotsSpan<ContiguousArray.Index, SlotIndex>
    @usableFromInline
    let ticks: ContiguousSpan<ComponentTicks>

    @usableFromInline
    init(mask: ChangeFilterMask, indices: SlotsSpan<ContiguousArray.Index, SlotIndex>, ticks: ContiguousSpan<ComponentTicks>) {
        self.mask = mask
        self.indices = indices
        self.ticks = ticks
    }
}

@usableFromInline
enum ChangeFilterStrategy {
    case none
    case fast(ContiguousArray<ChangeFilterAccessor>)
    case slow
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
    static func makeChangeFilterMasks(_ filters: Set<ChangeFilter>) -> [ComponentTag: ChangeFilterMask] {
        guard !filters.isEmpty else { return [:] }
        var masks: [ComponentTag: ChangeFilterMask] = [:]
        masks.reserveCapacity(filters.count)
        for filter in filters {
            var mask = masks[filter.tag] ?? []
            switch filter.kind {
            case .added:
                mask.insert(.added)
            case .changed:
                mask.insert(.changed)
            }
            masks[filter.tag] = mask
        }
        return masks
    }

    @inlinable @inline(__always)
    func makeSlotSpans(_ coordinator: Coordinator) -> ([SlotsSpan<ContiguousArray.Index, SlotIndex>], [SlotsSpan<ContiguousArray.Index, SlotIndex>])? {
        var requiredCapacity = backstageComponents.count
        for component in repeat (each T).self {
            if component is any OptionalQueriedComponent.Type { continue }
            if component == WithEntityID.self { continue }
            if component.QueriedComponent.self == Never.self { continue }
            requiredCapacity &+= 1
        }

        var required: [SlotsSpan<ContiguousArray.Index, SlotIndex>] = []
        required.reserveCapacity(requiredCapacity)

        func appendRequired(for tag: ComponentTag) -> Bool {
            guard let array = coordinator.pool.components[tag], !array.componentsToEntites.isEmpty else {
                return false
            }
            required.append(array.entityToComponents)
            return true
        }

        for component in repeat (each T).self {
            if component is any OptionalQueriedComponent.Type { continue }
            if component == WithEntityID.self { continue }
            if component.QueriedComponent.self == Never.self { continue }
            guard appendRequired(for: component.QueriedComponent.componentTag) else {
                return nil
            }
        }

        for tag in backstageComponents {
            guard appendRequired(for: tag) else {
                return nil
            }
        }

        var excluded: [SlotsSpan<ContiguousArray.Index, SlotIndex>] = []
        excluded.reserveCapacity(excludedComponents.count)

        for tag in excludedComponents {
            guard let array = coordinator.pool.components[tag], !array.componentsToEntites.isEmpty else {
                continue
            }
            excluded.append(array.entityToComponents)
        }

        return (required, excluded)
    }

    @inlinable @inline(__always)
    func prepareChangeFilterAccessors(_ accessors: (repeat TypedAccess<each T>)) -> ContiguousArray<ChangeFilterAccessor>? {
        guard !changeFilterMasks.isEmpty else { return nil }

        var prepared: ContiguousArray<ChangeFilterAccessor> = []
        prepared.reserveCapacity(changeFilterMasks.count)

        for access in repeat each accessors {
            guard let mask = changeFilterMasks[access.tag] else { continue }
            prepared.append(ChangeFilterAccessor(mask: mask, indices: access.indices, ticks: access.ticks))
        }

        // TODO: This is silly, instead throwing stuff away, I should just fill up the missing pieces which are not in the accessors.
        guard prepared.count == changeFilterMasks.count else { return nil }
        return prepared
    }

    @inlinable @inline(__always)
    static func passes(
        slot: SlotIndex,
        requiredComponents: UnsafeBufferPointer<SlotsSpan<ContiguousArray.Index, SlotIndex>>,
        excludedComponents: UnsafeBufferPointer<SlotsSpan<ContiguousArray.Index, SlotIndex>>
    ) -> Bool {
        for component in requiredComponents where component[slot] == .notFound {
            // Entity does not have all required components, skip.
            return false
        }

        for component in excludedComponents where component[slot] != .notFound {
            // Entity has at least one excluded component, skip.
            return false
        }

        return true
    }

    @inlinable @inline(__always)
    func satisfiesChangeFilters(_ context: QueryContext, entityID: Entity.ID) -> Bool {
        guard !changeFilterMasks.isEmpty else { return true }
        guard let snapshot = context.systemTickSnapshot else { return false }
        for (tag, mask) in changeFilterMasks {
            guard let ticks = context.coordinator.pool.componentTicks(for: tag, entityID: entityID) else {
                return false
            }
            if mask.contains(.added) && !ticks.isAdded(since: snapshot.lastRun, upTo: snapshot.thisRun) {
                return false
            }
            if mask.contains(.changed) && !ticks.isChanged(since: snapshot.lastRun, upTo: snapshot.thisRun) {
                return false
            }
        }
        return true
    }

    @inlinable @inline(__always)
    func satisfiesChangeFiltersFast(
        systemTickSnapshot: Coordinator.SystemTickSnapshot?,
        changeAccessors: ContiguousArray<ChangeFilterAccessor>,
        entityID: Entity.ID
    ) -> Bool {
        guard !changeFilterMasks.isEmpty else { return true }
        guard let snapshot = systemTickSnapshot else { return false }
        guard changeAccessors.count == changeFilterMasks.count else { return false }

        let addedMask = ChangeFilterMask.added.rawValue
        let changedMask = ChangeFilterMask.changed.rawValue

        return changeAccessors.withUnsafeBufferPointer { accessors in
            var index = 0
            while index < accessors.count {
                let accessor = accessors[index]
                let denseIndex = accessor.indices[entityID.slot]
                guard denseIndex != .notFound else { return false }
                let ticksPointer = accessor.ticks.mutablePointer(at: denseIndex)
                let ticks = ticksPointer.pointee
                let mask = accessor.mask.rawValue
                if mask & addedMask != 0 && !ticks.isAdded(since: snapshot.lastRun, upTo: snapshot.thisRun) {
                    return false
                }
                if mask & changedMask != 0 && !ticks.isChanged(since: snapshot.lastRun, upTo: snapshot.thisRun) {
                    return false
                }
                index &+= 1
            }
            return true
        }
    }

    @inlinable @inline(__always)
    func entitySatisfiesChangeFilters(
        _ context: QueryContext,
        systemTickSnapshot: Coordinator.SystemTickSnapshot?,
        fastAccessors: ContiguousArray<ChangeFilterAccessor>,
        entityID: Entity.ID
    ) -> Bool {
        guard !changeFilterMasks.isEmpty else { return true }
        return satisfiesChangeFiltersFast(
            systemTickSnapshot: systemTickSnapshot,
            changeAccessors: fastAccessors,
            entityID: entityID
        )
    }

    @inlinable @inline(__always)
    public func perform(_ context: some QueryContextConvertible, _ handler: (repeat (each T).ResolvedType) -> Void) {
        let context = context.queryContext
        let baseSlots = getCachedBaseSlots(context.coordinator)
        guard !baseSlots.isEmpty else { return }
        guard let (requiredComponents, excludedComponents) = makeSlotSpans(context.coordinator) else { return }
        // TODO: Use RigidArray or TailAllocated here

        let baseCount = baseSlots.count
        guard baseCount > 0 else { return }
        guard let basePointer = baseSlots.buffer else { return }

        let tickSnapshot = context.systemTickSnapshot
        let indices = context.coordinator.indices.generationView
        withTypedBuffers(&context.coordinator.pool, changeTick: context.coordinator.changeTick) { (accessors: repeat TypedAccess<each T>) in
            let strategy: ChangeFilterStrategy = if changeFilterMasks.isEmpty {
                .none
            } else if let prepared = prepareChangeFilterAccessors((repeat each accessors)) {
                .fast(prepared)
            } else {
                .slow
            }

            let indicesPointer = indices.pointer
            let otherCount = requiredComponents.count
            let excludedCount = excludedComponents.count

            requiredComponents.withUnsafeBufferPointer { otherBuffer in
                excludedComponents.withUnsafeBufferPointer { excludedBuffer in
                    @inline(__always)
                    func passesMembership(_ slot: SlotIndex) -> Bool {
                        var index = 0
                        while index < otherCount {
                            if otherBuffer[index][slot] == .notFound {
                                return false
                            }
                            index &+= 1
                        }

                        var excludedIndex = 0
                        while excludedIndex < excludedCount {
                            if excludedBuffer[excludedIndex][slot] != .notFound {
                                return false
                            }
                            excludedIndex &+= 1
                        }

                        return true
                    }

                    switch strategy {
                    case .none:
                        var baseIndex = 0
                        while baseIndex < baseCount {
                            let slot = basePointer.advanced(by: baseIndex).pointee
                            baseIndex &+= 1

                            guard passesMembership(slot) else { continue }

                            let generation = indicesPointer.advanced(by: slot.rawValue).pointee
                            let entityID = Entity.ID(
                                slot: slot,
                                generation: isQueryingForEntityID ? generation : 0
                            )

                            handler(repeat (each T).makeResolved(access: each accessors, entityID: entityID))
                        }

                    case .fast(let fastChangeAccessors):
                        guard let snapshot = tickSnapshot else { return }
                        let lastRun = snapshot.lastRun
                        let thisRun = snapshot.thisRun
                        let addedMask = ChangeFilterMask.added.rawValue
                        let changedMask = ChangeFilterMask.changed.rawValue

                        fastChangeAccessors.withUnsafeBufferPointer { changeBuffer in
                            let changeCount = changeBuffer.count

                            @inline(__always)
                            func passesChangeFilters(_ slot: SlotIndex) -> Bool {
                                var changeIndex = 0
                                while changeIndex < changeCount {
                                    let accessor = changeBuffer[changeIndex]
                                    let denseIndex = accessor.indices[slot]
                                    if denseIndex == .notFound {
                                        return false
                                    }

                                    let ticks = accessor.ticks.mutablePointer(at: denseIndex).pointee
                                    let mask = accessor.mask.rawValue

                                    if mask & addedMask != 0 && !ticks.isAdded(since: lastRun, upTo: thisRun) {
                                        return false
                                    }
                                    if mask & changedMask != 0 && !ticks.isChanged(since: lastRun, upTo: thisRun) {
                                        return false
                                    }

                                    changeIndex &+= 1
                                }
                                return true
                            }

                            var baseIndex = 0
                            while baseIndex < baseCount {
                                let slot = basePointer.advanced(by: baseIndex).pointee
                                baseIndex &+= 1

                                guard passesMembership(slot) else { continue }
                                guard passesChangeFilters(slot) else { continue }

                                let generation = indicesPointer.advanced(by: slot.rawValue).pointee
                                let entityID = Entity.ID(
                                    slot: slot,
                                    generation: isQueryingForEntityID ? generation : 0
                                )

                                handler(repeat (each T).makeResolved(access: each accessors, entityID: entityID))
                            }
                        }

                    case .slow:
                        var baseIndex = 0
                        while baseIndex < baseCount {
                            let slot = basePointer.advanced(by: baseIndex).pointee
                            baseIndex &+= 1

                            guard passesMembership(slot) else { continue }

                            let generation = indicesPointer.advanced(by: slot.rawValue).pointee
                            let fullID = Entity.ID(slot: slot, generation: generation)
                            guard satisfiesChangeFilters(context, entityID: fullID) else { continue }

                            let entityID = isQueryingForEntityID
                                ? fullID
                                : Entity.ID(slot: slot, generation: 0)

                            handler(repeat (each T).makeResolved(access: each accessors, entityID: entityID))
                        }
                    }
                }
            }
        }
    }
}

extension Query {
    @inlinable @inline(__always)
    public func performPreloaded(_ context: some QueryContextConvertible, _ handler: (repeat (each T).ResolvedType) -> Void) {
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
    }

    @inlinable @inline(__always)
    public func performGroup(_ context: some QueryContextConvertible, requireGroup: Bool = false, _ handler: (repeat (each T).ResolvedType) -> Void) {
//        let context = context.queryContext
//        let tickSnapshot = context.systemTickSnapshot
//
//        // Prefer a best-fitting group if available; otherwise fall back to cached slots.
//        let best = context.coordinator.bestGroup(for: querySignature)
//        let slotsSlice: ArraySlice<SlotIndex>
//        let exactGroupMatch: Bool
//        let owned: ComponentSignature
//        if let best {
//            slotsSlice = best.slots
//            exactGroupMatch = best.exact
//            owned = best.owned
//        } else if !requireGroup {
//            // No group found for query, fall back to precomputed slots.
//            slotsSlice = context.coordinator.pool.slots(
//                repeat (each T).self,
//                included: backstageComponents,
//                excluded: excludedComponents
//            )[...]
//            exactGroupMatch = false
//            owned = ComponentSignature()
//            print("No group found for query, falling back to precomputed slots. Consider adding a group matching this query.")
//        } else {
//            slotsSlice = []
//            exactGroupMatch = false
//            owned = ComponentSignature()
//            print("No group found for query. Consider adding a group matching this query.")
//        }
//
//        if exactGroupMatch {
//            withUnsafePointer(to: context.coordinator.indices) { indices in
//                withTypedBuffers(&context.coordinator.pool, changeTick: context.coordinator.changeTick) { (accessors: repeat TypedAccess<each T>) in
//                    let fastChangeAccessors = changeFilterMasks.isEmpty
//                        ? nil
//                        : prepareChangeFilterAccessors((repeat each accessors))
//                    // Enumerate dense indices directly: 0..<size aligned across all owned storages
//                    for (denseIndex, slot) in slotsSlice.enumerated() {
//                        let generation = indices.pointee[generationFor: slot]
//                        let fullID = Entity.ID(
//                            slot: SlotIndex(rawValue: slot.rawValue),
//                            generation: generation
//                        )
//                        guard entitySatisfiesChangeFilters(
//                            context,
//                            systemTickSnapshot: tickSnapshot,
//                            fastAccessors: fastChangeAccessors,
//                            entityID: fullID
//                        ) else { continue }
//                        let entityID = isQueryingForEntityID ? fullID : Entity.ID(
//                            slot: SlotIndex(rawValue: slot.rawValue),
//                            generation: 0
//                        )
//                        handler(repeat (each T).makeResolvedDense(access: each accessors, denseIndex: denseIndex, entityID: entityID))
//                    }
//                }
//            }
//        } else {
//            let querySignature = self.signature
//            let excludedSignature = self.excludedSignature
//            withUnsafePointer(to: context.coordinator.indices) { indices in
//                withTypedBuffers(&context.coordinator.pool, changeTick: context.coordinator.changeTick) { (accessors: repeat TypedAccess<each T>) in
//                    let fastChangeAccessors = changeFilterMasks.isEmpty
//                        ? nil
//                        : prepareChangeFilterAccessors((repeat each accessors))
//                    // Enumerate dense indices directly: 0..<size aligned across all owned storages
//                    for (denseIndex, slot) in slotsSlice.enumerated() {
//                        // Skip entities that don't satisfy the query when reusing a non-exact group (future use).
//                        // TODO: Optional components are ignored.
//                        let entitySignature = context.coordinator.entitySignatures[slot.index]
//                        guard entitySignature.isSuperset(of: querySignature, isDisjoint: excludedSignature) else {
//                            continue
//                        }
//                        let generation = indices.pointee[generationFor: slot]
//                        let fullID = Entity.ID(
//                            slot: SlotIndex(rawValue: slot.rawValue),
//                            generation: generation
//                        )
//                        if !entitySatisfiesChangeFilters(
//                            context,
//                            systemTickSnapshot: tickSnapshot,
//                            fastAccessors: fastChangeAccessors,
//                            entityID: fullID
//                        ) { continue }
//                        let entityID = isQueryingForEntityID ? fullID : Entity.ID(
//                            slot: SlotIndex(rawValue: slot.rawValue),
//                            generation: 0
//                        )
//
//                        @inline(__always)
//                        func resolve<C: Component>(_ type: C.Type, access: TypedAccess<C>, denseIndex: Int, entityID: Entity.ID, owned: ComponentSignature) -> C.ResolvedType {
//                            if owned.contains(C.componentTag) { // TODO: Does this `if` actually help with performance?
//                                type.makeResolvedDense(access: access, denseIndex: denseIndex, entityID: entityID)
//                            } else {
//                                type.makeResolved(access: access, entityID: entityID)
//                            }
//                        }
//                        handler(repeat resolve((each T).self, access: each accessors, denseIndex: denseIndex, entityID: entityID, owned: owned))
//                    }
//                }
//            }
//        }
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
//        let context = context.queryContext
//        let slots = getCachedPreFilteredSlots(context.coordinator)
//
//        let accessors = withTypedBuffers(&context.coordinator.pool, changeTick: context.coordinator.changeTick) { (accessors: repeat TypedAccess<each T>) in
//            (repeat each accessors)
//        }
//        var entityIDs: [Entity.ID] = []
//        entityIDs.reserveCapacity(slots.count)
//        for slot in slots {
//            let fullID = Entity.ID(slot: slot, generation: context.coordinator.indices[generationFor: slot])
//            guard satisfiesChangeFilters(context, entityID: fullID) else { continue }
//            let entityID = isQueryingForEntityID ? fullID : Entity.ID(slot: slot, generation: 0)
//            entityIDs.append(entityID)
//        }
//
//        return LazyWritableQuerySequence(
//            entityIDs: entityIDs,
//            accessors: repeat each accessors
//        )
        fatalError()
    }
}
