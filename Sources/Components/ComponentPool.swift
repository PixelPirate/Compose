struct ComponentPool {
    private(set) var components: [ComponentTag: AnyComponentArray] = [:]

    init(components: [ComponentTag : AnyComponentArray] = [:]) {
        self.components = components
    }

    init<each T: Component>(_ elements: repeat (ComponentTag, ComponentArray<each T>)) {
        var newComponents: [ComponentTag : AnyComponentArray] = [:]
        for element in repeat each elements {
            newComponents[element.0] = AnyComponentArray(element.1)
        }
        components = newComponents
    }
}

extension ComponentPool {
    mutating func append<C: Component>(_ component: C, for enitityID: Entity.ID) {
        components[C.componentTag]?.append(component, id: enitityID)
    }

    mutating func remove<C: Component>(_ componentType: C.Type = C.self, _ entityID: Entity.ID) {
        components[C.componentTag]?.remove(entityID)
    }

    mutating func remove(_ enitityID: Entity.ID) {
        components = components.mapValues {
            var array = $0
            array.remove(enitityID)
            return array
        }
    }

    func entities<each C: Component>(_ components: repeat (each C).Type) -> [Entity.ID] {
        // Collect the AnyComponentArray for each requested component type.
        var arrays: [AnyComponentArray] = [] // inline array

        for component in repeat each components {
            let tag = component.componentTag
            // If any tag is missing or empty, there can be no matches.
            guard let array = self.components[tag], !array.entityToComponents.isEmpty else {
                return []
            }
            arrays.append(array)
        }

        // Sort by ascending number of entities to minimize membership checks.
        arrays.sort { lhs, rhs in
            lhs.entityToComponents.count < rhs.entityToComponents.count
        }

        // Take the smallest set of IDs as the candidate base.
        let smallest = arrays[0]
        if arrays.count == 1 {
            return Array(smallest.entityToComponents.keys)
        }

        // Prepare the remaining dictionaries for O(1) membership checks.
        let others = arrays.dropFirst().map { $0.entityToComponents }

        // Filter candidate IDs by ensuring presence in all other component maps.
        var result: [Entity.ID] = []
        result.reserveCapacity(smallest.entityToComponents.count)
        for id in smallest.entityToComponents.keys {
            var presentInAll = true
            for dict in others {
                if dict[id] == nil { presentInAll = false; break }
            }
            if presentInAll { result.append(id) }
        }
        return result
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
