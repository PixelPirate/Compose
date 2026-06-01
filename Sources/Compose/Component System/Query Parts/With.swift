public struct With<C: Component>: Component, Sendable {
    public static var componentTag: ComponentTag { C.componentTag }

    public typealias Wrapped = C
}
