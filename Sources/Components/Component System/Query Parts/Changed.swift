public struct Changed<C: Component>: Component {
    public static var componentTag: ComponentTag { C.componentTag }
}
