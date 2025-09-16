//
//  ComponentPool.swift
//  Components
//
//  Created by Patrick Horlebein (extern) on 11.09.25.
//

struct ComponentPool {
    private(set) var components: [ComponentTag: ComponentArray<any Component>] = [:]
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
