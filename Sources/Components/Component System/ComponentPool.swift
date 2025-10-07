public struct ComponentPool {
    private(set) var components: [ComponentTag: AnyComponentArray] = [:]

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
    }

    @usableFromInline
    mutating func append<C: Component>(_ component: C, for entityID: Entity.ID) {
        let array = components[C.componentTag] ?? AnyComponentArray(ComponentArray<C>())
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

    @usableFromInline
    func slots<each C: Component>(
        _ components: repeat (each C).Type,
        included: Set<ComponentTag> = [],
        excluded: Set<ComponentTag> = []
    ) -> [SlotIndex] {
        // Collect the AnyComponentArray for each requested component type.
        var arrays: [AnyComponentArray] = []
        var excludedArrays: [AnyComponentArray] = []
        var queryingForEntityID = false

        for component in repeat each components {
            let tag = component.QueriedComponent.componentTag
            if component == WithEntityID.self {
                queryingForEntityID = true
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
            // If any tag is missing or empty, there can be no matches.
            guard let array = self.components[tag], !array.componentsToEntites.isEmpty else {
                continue
            }
            excludedArrays.append(array)
        }

        guard !arrays.isEmpty else {
            if queryingForEntityID {
                // TODO: Optimize
                return Array(Set(self.components.values.flatMap { $0.componentsToEntites }))
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
                return Array(smallest.componentsToEntites)
            } else {
                return smallest.componentsToEntites.filter { slot in
                    excludedArrays.allSatisfy { componentArray in
                        !componentArray.entityToComponents.indices.contains(slot.rawValue) || componentArray.entityToComponents[slot.rawValue] == nil
                    }
                }
                .map {
                    $0
                }
            }
        }

        // Prepare the remaining dictionaries for O(1) membership checks.
        let others = arrays.dropFirst().map { $0.entityToComponents }

        // Filter candidate IDs by ensuring presence in all other component maps.
        var result: [SlotIndex] = []
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
    func baseAndOthers<each C: Component>(
        _ components: repeat (each C).Type,
        included: Set<ComponentTag> = [],
        excluded: Set<ComponentTag> = []
    )
    -> (base: ContiguousArray<SlotIndex>, others: [ContiguousArray<Array.Index?>], excluded: [ContiguousArray<Array.Index?>])?
    {
        // Collect the AnyComponentArray for each requested component type.
        var arrays: [AnyComponentArray] = []
        var excludedArrays: [AnyComponentArray] = []
        var isQueryingForEntityIDs = false

        for component in repeat each components {
            let tag = component.QueriedComponent.componentTag
            if component == WithEntityID.self {
                isQueryingForEntityIDs = true
            }
            guard component.QueriedComponent.self != Never.self else {
                continue
            }
            // If any tag is missing or empty, there can be no matches.
            guard let array = self.components[tag], !array.componentsToEntites.isEmpty else {
                return nil
            }
            arrays.append(array)
        }

        for tag in included {
            // If any tag is missing or empty, there can be no matches.
            guard let array = self.components[tag], !array.componentsToEntites.isEmpty else {
                return nil
            }
            arrays.append(array)
        }

        for tag in excluded {
            // If any tag is missing or empty, there can be no matches.
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
            }
            return ([], [], excludedArrays.map(\.entityToComponents))
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

    @usableFromInline
    func base<each C: Component>(
        _ components: repeat (each C).Type,
        included: Set<ComponentTag> = []
    ) -> ContiguousArray<SlotIndex>? {
        // Collect the AnyComponentArray for each requested component type.
        var arrays: [AnyComponentArray] = []

        for component in repeat each components {
            let tag = component.componentTag
            guard component.QueriedComponent.self != Never.self else {
                continue
            }
            // If any tag is missing or empty, there can be no matches.
            guard let array = self.components[tag], !array.componentsToEntites.isEmpty else {
                return nil
            }
            arrays.append(array)
        }

        for tag in included {
            // If any tag is missing or empty, there can be no matches.
            guard let array = self.components[tag], !array.componentsToEntites.isEmpty else {
                return nil
            }
            arrays.append(array)
        }

        return arrays.min { lhs, rhs in
            lhs.componentsToEntites.count < rhs.componentsToEntites.count
        }?.componentsToEntites
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
