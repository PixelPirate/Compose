struct ComponentPool {
    private(set) var components: [ComponentTag: ComponentArray<any Component>] = [:]
    // TODO: Array<any Component> is an issue, because we have to case every single component.
    // It would be better to have an actual typed array, but hide the whole typed array in an erased wrapper
    // then there only needs to be one single case for the array as a whole.
}

extension ComponentPool {
    mutating func append<C: Component>(_ component: C, for enitityID: Entity.ID) {
        components[C.componentTag]?.append(component, to: enitityID)
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

    // TODO: This algorithm is complete shit.
    func entities<each C: Component>(_ components: repeat (each C).Type) -> [Entity.ID] {
        var result: Set<Entity.ID> = []
        var initial = true
        for component in repeat each components {
            let tag = component.componentTag
            let new = self.components[tag]!.entityIDsInStorageOrder()
            if initial {
                initial = false
                result.formUnion(new)
            } else {
                result.formIntersection(new)
            }
        }
        return Array(result)
    }

    subscript<C: Component>(_ componentType: C.Type = C.self, _ entityID: Entity.ID) -> C {
        components[C.componentTag]![entityID] as! C
    }

    subscript(_ componentTag: ComponentTag, _ entityID: Entity.ID) -> any Component {
        get {
            components[componentTag]![entityID]
        }
        set {
            components[componentTag]![entityID] = newValue
        }
    }

    mutating func modify<C: Component>(_ componentType: C.Type = C.self, _ entityID: Entity.ID, map: (inout C) -> Void) {
        var component = components[C.componentTag]![entityID] as! C
        map(&component)
        components[C.componentTag]![entityID] = component
    }
}
