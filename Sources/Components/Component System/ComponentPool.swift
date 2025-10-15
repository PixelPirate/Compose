public struct ComponentPool {
    @usableFromInline
    private(set) var components: [ComponentTag: AnyComponentArray] = [:]
    private var ensuredEntityID: Entity.ID?

    public init(components: [ComponentTag : AnyComponentArray] = [:]) {
        self.components = components
    }

    public init<each T: Component>(_ elements: repeat (ComponentTag, ComponentArray<each T>)) {
        var newComponents: [ComponentTag : AnyComponentArray] = [:]
        for element in repeat each elements {
            newComponents[element.0] = AnyComponentArray(element.1)
        }
        components = newComponents
    }
}

extension ComponentPool {
    @usableFromInline
    mutating func ensureSparseSetCount(includes entityID: Entity.ID) {
        for component in components.values {
            component.ensureEntity(entityID)
        }
        ensuredEntityID = entityID
    }

    @usableFromInline
    mutating func append<C: Component>(_ component: C, for entityID: Entity.ID) {
        let array = components[C.componentTag] ?? {
            var newArray = AnyComponentArray(ComponentArray<C>())
            newArray.reserveCapacity(minimumComponentCapacity: 50, minimumSlotCapacity: 500)
            newArray.ensureEntity(ensuredEntityID ?? entityID)
            return newArray
        }()
        array.append(component, id: entityID)
        components[C.componentTag] = array
    }

    @usableFromInline
    mutating func remove<C: Component>(_ componentType: C.Type = C.self, _ entityID: Entity.ID) {
        guard let array = components[C.componentTag] else { return }
        array.remove(entityID)
        components[C.componentTag] = array
    }

    @usableFromInline
    mutating func remove(_ componentTag: ComponentTag, _ entityID: Entity.ID) {
        guard let array = components[componentTag] else { return }
        array.remove(entityID)
        components[componentTag] = array
    }

    @usableFromInline
    mutating func remove(_ entityID: Entity.ID) {
        for component in components.values {
            component.remove(entityID)
        }
    }
    
    /// Precomputes all valid slot indices. Has some upfront cost, but worth it for iterating large amounts of entities.
    @usableFromInline
    func slots<each C: Component>(
        _ components: repeat (each C).Type,
        included: Set<ComponentTag> = [],
        excluded: Set<ComponentTag> = []
    ) -> ContiguousArray<SlotIndex> {
        // Collect the AnyComponentArray for each requested component type.
        var arrays: [AnyComponentArray] = []
        var excludedArrays: [AnyComponentArray] = []
        var isQueryingForEntityIDs = false

        for component in repeat each components {
            if component is any OptionalQueriedComponent.Type {
                continue // Optional components can be skipped here.
            }
            let tag = component.QueriedComponent.componentTag
            if component == WithEntityID.self {
                isQueryingForEntityIDs = true
            }
            guard component.QueriedComponent.self != Never.self else {
                continue
            }
            // If any tag is missing or empty, there can be no matches.
            guard let array = self.components[tag], !array.componentsToEntites.isEmpty else {
                return []
            }
            arrays.append(array)
        }

        for tag in included {
            // If any tag is missing or empty, there can be no matches.
            guard let array = self.components[tag], !array.componentsToEntites.isEmpty else {
                return []
            }
            arrays.append(array)
        }

        for tag in excluded {
            // If any tag is missing or empty, we can skip this exclude.
            guard let array = self.components[tag], !array.componentsToEntites.isEmpty else {
                continue
            }
            excludedArrays.append(array)
        }

        guard !arrays.isEmpty else {
            if isQueryingForEntityIDs {
                let candidates = ContiguousArray(Set(self.components.values.flatMap { $0.componentsToEntites }))
                if excluded.isEmpty {
                    return candidates
                } else {
                    return candidates.filter { slot in
                        excludedArrays.allSatisfy { componentArray in
                            !componentArray.entityToComponents.indices.contains(slot.rawValue) || componentArray.entityToComponents[slot.rawValue] == nil
                        }
                    }
                }
            }
            return []
        }

        // Sort by ascending number of entities to minimise membership checks.
        arrays.sort { lhs, rhs in
            lhs.componentsToEntites.count < rhs.componentsToEntites.count
        }

        // Take the smallest set of IDs as the candidate base.
        let smallest = arrays[0]
        if arrays.count == 1 {
            if excluded.isEmpty {
                return ContiguousArray(smallest.componentsToEntites)
            } else {
                return smallest.componentsToEntites.filter { slot in
                    excludedArrays.allSatisfy { componentArray in
                        !componentArray.entityToComponents.indices.contains(slot.rawValue) || componentArray.entityToComponents[slot.rawValue] == nil
                    }
                }
            }
        }

        // Prepare the remaining dictionaries for O(1) membership checks.
        let others = arrays.dropFirst().map { $0.entityToComponents }

        // Filter candidate IDs by ensuring presence in all other component maps.
        var result: ContiguousArray<SlotIndex> = []
        result.reserveCapacity(smallest.componentsToEntites.count)
        for slot in smallest.componentsToEntites {
            var presentInAll = true
            for sparseList in others {
                if sparseList[slot.rawValue] == nil {
                    presentInAll = false
                    break
                }
            }
            for excluded in excludedArrays where excluded.entityToComponents[slot.rawValue] != nil {
                presentInAll = false
                break
            }
            if presentInAll {
                result.append(slot)
            }
        }
        return result
    }

    @usableFromInline
    func matches<each C: Component>(slot: SlotIndex, query: Query<repeat each C>) -> Bool {
        for component in repeat (each C).self {
            if component is any OptionalQueriedComponent.Type {
                continue // Optional components can be skipped here.
            }
            if component == WithEntityID.self {
                continue
            }
            guard component.QueriedComponent.self != Never.self else {
                continue
            }
            // If any tag is missing or empty, there can be no matches.
            let tag = component.QueriedComponent.componentTag
            guard
                let array = self.components[tag],
                array.entityToComponents[slot.rawValue] != nil
            else {
                return false
            }
        }

        for tag in query.backstageComponents {
            // If any tag is missing or empty, there can be no matches.
            guard let array = self.components[tag], array.entityToComponents[slot.rawValue] != nil else {
                return false
            }
        }

        for tag in query.excludedComponents {
            // If any tag is missing or empty, we can skip this exclude.
            guard let array = self.components[tag] else {
                continue
            }
            guard array.entityToComponents[slot.rawValue] == nil else {
                return false
            }
        }

        return true
    }

    /// Returns the base slots to drive iteration and all other sparse arrays used to filter entities during iteration.
    /// This requires some filtering during iteration but the up front cost of this call is negligible.
    @usableFromInline
    func baseAndOthers<each C: Component>(
        _ components: repeat (each C).Type,
        included: Set<ComponentTag> = [],
        excluded: Set<ComponentTag> = []
    )
    -> (base: ContiguousArray<SlotIndex>, others: [ContiguousArray<Array.Index?>], excluded: [ContiguousArray<Array.Index?>])
    {
        // Collect the AnyComponentArray for each requested component type.
        var arrays: [AnyComponentArray] = []
        var excludedArrays: [AnyComponentArray] = []
        var isQueryingForEntityIDs = false

        for component in repeat each components {
            if component is any OptionalQueriedComponent.Type {
                continue // Optional components can be skipped here.
            }
            let tag = component.QueriedComponent.componentTag
            if component == WithEntityID.self {
                isQueryingForEntityIDs = true
            }
            guard component.QueriedComponent.self != Never.self else {
                continue
            }
            // If any tag is missing or empty, there can be no matches.
            guard let array = self.components[tag], !array.componentsToEntites.isEmpty else {
                return ([], [], [])
            }
            arrays.append(array)
        }

        for tag in included {
            // If any tag is missing or empty, there can be no matches.
            guard let array = self.components[tag], !array.componentsToEntites.isEmpty else {
                return ([], [], [])
            }
            arrays.append(array)
        }

        for tag in excluded {
            // If any tag is missing or empty, we can skip this exclude.
            guard let array = self.components[tag], !array.componentsToEntites.isEmpty else {
                continue
            }
            excludedArrays.append(array)
        }

        guard !arrays.isEmpty else {
            if isQueryingForEntityIDs {
                return (
                    ContiguousArray(Set(self.components.values.flatMap { $0.componentsToEntites })),
                    [],
                    excludedArrays.map(\.entityToComponents)
                )
            } else {
                return ([], [], [])
            }
        }

        guard arrays.count > 1 else {
            return (
                arrays[0].componentsToEntites,
                [],
                excludedArrays.map(\.entityToComponents)
            )
        }

        // Sort by ascending number of entities to minimize membership checks.
        arrays.sort { lhs, rhs in
            lhs.componentsToEntites.count < rhs.componentsToEntites.count
        }

        // Take the smallest set of IDs as the candidate base.
        let smallest = arrays[0]

        return (
            smallest.componentsToEntites,
            arrays.dropFirst().map(\.entityToComponents),
            excludedArrays.map(\.entityToComponents)
        )
    }

    /// Returns the base slots to drive iteration.
    /// This requires some filtering during iteration but the up front cost of this call is negligible.
    @usableFromInline
    func base<each C: Component>(
        _ components: repeat (each C).Type,
        included: Set<ComponentTag> = []
    ) -> ContiguousArray<SlotIndex> {
        // Collect the AnyComponentArray for each requested component type.
        var arrays: [AnyComponentArray] = []
        var isQueryingForEntityIDs = false

        for component in repeat each components {
            if component is any OptionalQueriedComponent.Type {
                continue // Optional components can be skipped here.
            }
            let tag = component.QueriedComponent.componentTag
            if component == WithEntityID.self {
                isQueryingForEntityIDs = true
            }
            guard component.QueriedComponent.self != Never.self else {
                continue
            }
            // If any tag is missing or empty, there can be no matches.
            guard let array = self.components[tag], !array.componentsToEntites.isEmpty else {
                return []
            }
            arrays.append(array)
        }

        for tag in included {
            // If any tag is missing or empty, there can be no matches.
            guard let array = self.components[tag], !array.componentsToEntites.isEmpty else {
                return []
            }
            arrays.append(array)
        }

        guard !arrays.isEmpty else {
            if isQueryingForEntityIDs {
                return ContiguousArray(Set(self.components.values.flatMap { $0.componentsToEntites }))
            } else {
                return []
            }
        }

        guard arrays.count > 1 else {
            return arrays[0].componentsToEntites
        }

        return arrays.min { lhs, rhs in
            lhs.componentsToEntites.count < rhs.componentsToEntites.count
        }?.componentsToEntites ?? []
    }

    subscript<C: Component>(_ componentType: C.Type = C.self) -> ComponentArrayBox<C> {
        _read {
            yield components[C.componentTag]!.typedBox(C.self)
        }
    }

    subscript<C: Component>(_ componentType: C.Type = C.self, _ entityID: Entity.ID) -> C {
        _read {
            yield components[C.componentTag]![entityID: entityID] as! C
        }
    }

    subscript(_ componentTag: ComponentTag, _ entityID: Entity.ID) -> any Component {
        _read {
            yield components[componentTag]![entityID: entityID]
        }
        _modify {
            yield &components[componentTag]![entityID: entityID]
        }
    }
}

@discardableResult
@usableFromInline
func withTypedBuffers<each C: ComponentResolving, R>(
    _ pool: inout ComponentPool,
    _ body: (repeat TypedAccess<each C>) throws -> R
) rethrows -> R {
    @inline(__always)
    func buildTuple() -> (repeat TypedAccess<each C>) {
        return (repeat tryMakeAccess((each C).self))
    }

    @inline(__always)
    func tryMakeAccess<D: ComponentResolving>(_ type: D.Type) -> TypedAccess<D> {
        guard D.QueriedComponent.self != Never.self else { return TypedAccess<D>.empty }
        guard let anyArray = pool.components[D.QueriedComponent.componentTag] else {
            guard D.self is any OptionalQueriedComponent.Type else {
                fatalError("Unknown component.")
            }
            return TypedAccess<D>.empty
        }
        var result: TypedAccess<D>? = nil
        anyArray.withBuffer(D.QueriedComponent.self) { buffer, entitiesToIndices in
            result = TypedAccess(buffer: buffer, indices: entitiesToIndices)
            // Escaping the buffer here is bad, but we need a pack splitting in calls and recursive flatten in order to resolve this.
            // The solution would be a recursive function which would recursively call `withBuffer` on the head until the pack is empty, and then call `body` with all the buffers.
            // See: https://forums.swift.org/t/pitch-pack-destructuring-pack-splitting/79388/12
            // See: https://forums.swift.org/t/passing-a-parameter-pack-to-a-function-call-fails-to-compile/72243/15
        }
        return result.unsafelyUnwrapped
    }

    let built = buildTuple()
    return try body(repeat each built)
}
