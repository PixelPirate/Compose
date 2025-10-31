public struct Without<C: Component>: Component {
    public static var componentTag: ComponentTag { C.componentTag }
}
