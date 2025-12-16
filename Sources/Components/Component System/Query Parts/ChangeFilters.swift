/// Causes a query to only return results when `Component` got added since the querying system last ran.
/// This does also apply for a spawn with the given component.
public struct Added<C: Component>: Component {
    public static var componentTag: ComponentTag { C.componentTag }
}

/// Causes a query to only return results when `Component` was changed since the querying system last ran.
public struct Changed<C: Component>: Component {
    public static var componentTag: ComponentTag { C.componentTag }
}

/// Causes a query to only return results when `Component` was removed since the querying system last ran.
/// Destroying an entity does not trigger this filter.
/// - Note: Removals are deferred operations which only apply at the end of a schedule.
public struct Removed<C: Component>: Component {
    public static var componentTag: ComponentTag { C.componentTag }
}
