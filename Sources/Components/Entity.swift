//
//  Entity.swift
//  Components
//
//  Created by Patrick Horlebein (extern) on 16.09.25.
//


struct Entity {
    struct ID: Hashable { let rawValue: Int }
    let id: ID
    var signature = ComponentSignature()
}