//
//  SystemManager.swift
//  Components
//
//  Created by Patrick Horlebein (extern) on 12.09.25.
//

struct SystemManager {
    private var systems: [SystemID: any System] = [:]
    private var signatures: [SystemID: ComponentSignature] = [:]

    mutating func add(_ system: some System) {
        guard !systems.keys.contains(system.id) else {
            fatalError("System already registered.")
        }
        systems[system.id] = system
    }

    mutating func setSignature(_ signature: ComponentSignature, systemID: SystemID) {
        guard systems.keys.contains(systemID) else {
            fatalError("System not registered.")
        }
        signatures[systemID] = signature
    }

    mutating func remove(_ entity: Entity) {
        systems = systems.mapValues { system in
            var newSystem = system
            newSystem.entities.remove(entity.id)
            return newSystem
        }
    }

    mutating func updateSignature(_ signature: ComponentSignature, for entityID: Entity.ID) {
        systems = systems.mapValues { system in
            guard let systemSignature = signatures[system.id] else {
                return system
            }
            var newSystem = system
            if systemSignature.rawHashValue.isSubset(of: signature.rawHashValue) {
                newSystem.entities.insert(entityID)
            } else {
                newSystem.entities.remove(entityID)
            }
            return newSystem
        }
    }
}
