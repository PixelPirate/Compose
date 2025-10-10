//
//  Never.swift
//  Components
//
//  Created by Patrick Horlebein (extern) on 10.10.25.
//

extension Never: Component {
    public static let componentTag = ComponentTag(rawValue: -2)
    public typealias QueriedComponent = Never
}
