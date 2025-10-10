//
//  With.swift
//  Components
//
//  Created by Patrick Horlebein (extern) on 10.10.25.
//

public struct With<C: Component>: Component, Sendable {
    public static var componentTag: ComponentTag { C.componentTag }

    public typealias Wrapped = C
}
