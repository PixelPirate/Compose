public struct Added<C: Component>: Component {
    public static var componentTag: ComponentTag { C.componentTag }
}

public struct Changed<C: Component>: Component {
    public static var componentTag: ComponentTag { C.componentTag }
}

public struct Removed<C: Component>: Component {
    public static var componentTag: ComponentTag { C.componentTag }
}
