/// Causes a query to only return results when `Component` got added since the querying system last ran.
/// This does also apply for a spawn with the given component.
public struct Added<C: Component>: Component, ObservationFilter {
    public static var componentTag: ComponentTag { C.componentTag }
    public static var condition: ChangeFilter.Condition {
        .added
    }
}

/// Causes a query to only return results when `Component` was changed since the querying system last ran.
public struct Changed<C: Component>: Component, ObservationFilter {
    public static var componentTag: ComponentTag { C.componentTag }
    public static var condition: ChangeFilter.Condition {
        .changed
    }
}

/// Causes a query to only return results when `Component` was removed since the querying system last ran.
/// Destroying an entity does not trigger this filter.
/// - Note: Removals are deferred operations which only apply at the end of a schedule.
public struct Removed<C: Component>: Component, ObservationFilter {
    public static var componentTag: ComponentTag { C.componentTag }
    public static var condition: ChangeFilter.Condition {
        .removed
    }
}

public protocol ObservationFilter {
    associatedtype C: Component
    static var condition: ChangeFilter.Condition { get }
}

let x = Query {
    Write<Transform>.self
    Or {
        Changed<Body>.self
        Changed<Health>.self
    }
}

public struct Or<each F: ObservationFilter> {
    init() {}

    public init(@OrObservationBuilder body: () -> Or<repeat each F>) {
        self = body()
    }

    var filter: ChangeFilter {
        var result: Set<ChangeFilter.ComponentCondition> = []
        for filter in repeat (each F).self {
            result.insert(ChangeFilter.ComponentCondition(tag: filter.C.componentTag, condition: filter.condition))
        }
        return ChangeFilter(.or(result))
    }

    var includedComponents: Set<ComponentTag> {
        var result: Set<ComponentTag> = []
        for filter in repeat (each F).self {
            if filter.condition != .removed {
                result.insert(filter.C.componentTag)
            }
        }
        return result
    }

    var excludedComponents: Set<ComponentTag> {
        var result: Set<ComponentTag> = []
        for filter in repeat (each F).self {
            if filter.condition == .removed {
                result.insert(filter.C.componentTag)
            }
        }
        return result
    }
}

struct Transform: Component {
    static let componentTag = ComponentTag.makeTag()
}

struct Body: Component {
    static let componentTag = ComponentTag.makeTag()
}

struct Health: Component {
    static let componentTag = ComponentTag.makeTag()
}

@resultBuilder
public enum OrObservationBuilder {
    public static func buildExpression<C: ObservationFilter>(_ c: C.Type) -> Or<C> {
        Or<C>()
    }


    public static func buildPartialBlock<each T: ObservationFilter>(first: Or<repeat each T>) -> Or<repeat each T> {
        first
    }

    public static func buildPartialBlock<each T, each U>(
        accumulated: Or<repeat each T>,
        next: Or<repeat each U>
    ) -> Or<repeat each T, repeat each U> {
        Or<repeat each T,repeat each U>()
    }
}
