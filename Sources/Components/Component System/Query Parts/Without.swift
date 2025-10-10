//
//  Without.swift
//  Components
//
//  Created by Patrick Horlebein (extern) on 10.10.25.
//

public struct Without<C: Component>: Component {
    public static var componentTag: ComponentTag { C.componentTag }
}
