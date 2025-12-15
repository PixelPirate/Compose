/// Causes a query to only return results when `Component` got added in the previous frame. This does not apply for a spawn with the given component.
public struct Added<C: Component>: Component {
    public static var componentTag: ComponentTag { C.componentTag }
}

/// Causes a query to only return results when `Component` was changed in the previous frame.
public struct Changed<C: Component>: Component {
    public static var componentTag: ComponentTag { C.componentTag }
}
