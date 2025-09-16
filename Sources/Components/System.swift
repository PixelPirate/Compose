//
//  System.swift
//  Components
//
//  Created by Patrick Horlebein (extern) on 16.09.25.
//


protocol System {
    var id: SystemID { get }
    var entities: Set<Entity.ID> { get set }
    var signature: ComponentSignature { get }
}

struct SystemID: Hashable {
    let rawHashValue: Int

    init(name: String) {
        rawHashValue = name.hashValue
    }
}