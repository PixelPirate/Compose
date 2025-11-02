public struct Added<C: Component>: Component {
    public static var componentTag: ComponentTag { C.componentTag }
}
