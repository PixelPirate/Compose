public struct Changed<C: Component>: Component, Sendable {
    public static var componentTag: ComponentTag { C.componentTag }

    public typealias Wrapped = C
}
