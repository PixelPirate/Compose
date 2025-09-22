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
    mutating func ensureSparseSetCount(includes entityID: Entity.ID) {
        for component in components.values {
            component.ensureEntity(entityID)
        }
    }
    mutating func append<C: Component>(_ component: C, for entityID: Entity.ID) {
        components[C.componentTag, default: AnyComponentArray(ComponentArray<C>())].append(component, id: entityID)
    }

    mutating func remove<C: Component>(_ componentType: C.Type = C.self, _ entityID: Entity.ID) {
        remove(C.componentTag, entityID)
    }

    mutating func remove(_ componentTag: ComponentTag, _ entityID: Entity.ID) {
        components[componentTag]?.remove(entityID)
    }

    mutating func remove(_ enitityID: Entity.ID) {
        components = components.mapValues {
            var array = $0
            array.remove(enitityID)
            return array
        }
    }

    @usableFromInline
    func entities<each C: Component>(
        _ components: repeat (each C).Type,
        included: Set<ComponentTag> = [],
        excluded: Set<ComponentTag> = []
    ) -> [Entity.ID] {
        // Collect the AnyComponentArray for each requested component type.
        var arrays: [AnyComponentArray] = []
        var excludedArrays: [AnyComponentArray] = []

        for component in repeat each components {
            let tag = component.componentTag
            if !component.requiresStorage {
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

        // Sort by ascending number of entities to minimize membership checks.
        arrays.sort { lhs, rhs in
            lhs.componentsToEntites.count < rhs.componentsToEntites.count
        }

        // Take the smallest set of IDs as the candidate base.
        let smallest = arrays[0]
        if arrays.count == 1 {
            if excluded.isEmpty {
                return smallest.componentsToEntites.map { Entity.ID(slot: $0) }
            } else {
                return smallest.componentsToEntites.filter { slot in
                    excludedArrays.allSatisfy { componentArray in
                        !componentArray.entityToComponents.indices.contains(slot.rawValue) || componentArray.entityToComponents[slot.rawValue] == -1
                    }
                }
                .map {
                    Entity.ID(slot: $0)
                }
            }
        }

        // Prepare the remaining dictionaries for O(1) membership checks.
        let others = arrays.dropFirst().map { $0.entityToComponents }

        // Filter candidate IDs by ensuring presence in all other component maps.
        var result: [Entity.ID] = []
        result.reserveCapacity(smallest.componentsToEntites.count)
        for slot in smallest.componentsToEntites {
            var presentInAll = true
            for sparseList in others {
                if sparseList[slot.rawValue] == .notFound {
                    presentInAll = false
                    break
                }
            }
            for excluded in excludedArrays where excluded.entityToComponents[slot.rawValue] != .notFound {
                presentInAll = false
                break
            }
            if presentInAll {
                result.append(Entity.ID(slot: slot))
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
//    -> (base: ContiguousArray<SlotIndex>, others: [ContiguousArray<Array.Index>], excluded: [ContiguousArray<Array.Index>])?
    -> ContiguousArray<SlotIndex>?
    {
        // Collect the AnyComponentArray for each requested component type.
        var arrays: [AnyComponentArray] = []
//        var excludedArrays: [AnyComponentArray] = []

        for component in repeat each components {
            let tag = component.componentTag
            guard component.requiresStorage else {
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

//        for tag in excluded {
//            // If any tag is missing or empty, there can be no matches.
//            guard let array = self.components[tag], !array.componentsToEntites.isEmpty else {
//                continue
//            }
//            excludedArrays.append(array)
//        }

        // Sort by ascending number of entities to minimize membership checks.
//        arrays.sort { lhs, rhs in
//            lhs.componentsToEntites.count < rhs.componentsToEntites.count
//        }

        // Take the smallest set of IDs as the candidate base.
//        let smallest = arrays[0]

        return arrays.min { lhs, rhs in
            lhs.componentsToEntites.count < rhs.componentsToEntites.count
        }?.componentsToEntites

//        return (
//            smallest.componentsToEntites,
//            arrays.dropFirst().map(\.entityToComponents),
//            excludedArrays.map(\.entityToComponents)
//        )
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
