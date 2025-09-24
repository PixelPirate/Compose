//
//  SystemManager.swift
//  Components
//
//  Created by Patrick Horlebein (extern) on 12.09.25.
//

@usableFromInline
struct SystemManager {
    private var systems: [SystemID: any System] = [:]
    private var signatures: [SystemID: ComponentSignature] = [:]

    mutating func add(_ system: some System) {
        guard !systems.keys.contains(system.id) else {
            fatalError("System already registered.")
        }
        systems[system.id] = system
//        setSignature(system.signature, systemID: system.id)
    }

    mutating func setSignature(_ signature: ComponentSignature, systemID: SystemID) {
        guard systems.keys.contains(systemID) else {
            fatalError("System not registered.")
        }
        signatures[systemID] = signature
    }

    mutating func remove(_ entityID: Entity.ID) {
        systems = systems.mapValues { system in
            var newSystem = system
//            newSystem.entities.remove(entityID)
            return newSystem
        }
    }

    mutating func remove(_ systemID: SystemID) {
        systems.removeValue(forKey: systemID)
        signatures.removeValue(forKey: systemID)
    }

    mutating func updateSignature(_ signature: ComponentSignature, for entityID: Entity.ID) {
        systems = systems.mapValues { system in
            guard let systemSignature = signatures[system.id] else {
                return system
            }
            var newSystem = system
            if systemSignature.rawHashValue.isSubset(of: signature.rawHashValue) {
//                newSystem.entities.insert(entityID)
            } else {
//                newSystem.entities.remove(entityID)
            }
            return newSystem
        }
    }
}
