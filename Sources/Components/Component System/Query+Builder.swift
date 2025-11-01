public struct BuiltQuery<each T: Component & ComponentResolving> {
    @usableFromInline
    let composite: Query<repeat each T>
}

@resultBuilder
public enum QueryBuilder {
    public static func buildExpression<C: Component>(_ c: C.Type) -> BuiltQuery<C> {
        BuiltQuery(
            composite: Query<C>(
                backstageComponents: [],
                excludedComponents: [],
                addedComponents: [],
                changedComponents: [],
                isQueryingForEntityID: false
            )
        )
    }

    public static func buildExpression<C: Component>(_ c: Write<C>.Type) -> BuiltQuery<Write<C>> {
        BuiltQuery(
            composite: Query<Write<C>>(
                backstageComponents: [],
                excludedComponents: [],
                addedComponents: [],
                changedComponents: [],
                isQueryingForEntityID: false
            )
        )
    }

    public static func buildExpression<C: Component>(_ c: With<C>.Type) -> BuiltQuery< > {
        BuiltQuery(
            composite: Query< >(
                backstageComponents: [C.componentTag],
                excludedComponents: [],
                addedComponents: [],
                changedComponents: [],
                isQueryingForEntityID: false
            )
        )
    }

    public static func buildExpression<C: Component>(_ c: Without<C>.Type) -> BuiltQuery< > {
        BuiltQuery(
            composite: Query< >(
                backstageComponents: [],
                excludedComponents: [C.componentTag],
                addedComponents: [],
                changedComponents: [],
                isQueryingForEntityID: false
            )
        )
    }

    public static func buildExpression<C: Component>(_ c: Added<C>.Type) -> BuiltQuery< > {
        BuiltQuery(
            composite: Query< >(
                backstageComponents: [C.componentTag],
                excludedComponents: [],
                addedComponents: [C.componentTag],
                changedComponents: [],
                isQueryingForEntityID: false
            )
        )
    }

    public static func buildExpression<C: Component>(_ c: Changed<C>.Type) -> BuiltQuery< > {
        BuiltQuery(
            composite: Query< >(
                backstageComponents: [C.componentTag],
                excludedComponents: [],
                addedComponents: [],
                changedComponents: [C.componentTag],
                isQueryingForEntityID: false
            )
        )
    }

    public static func buildExpression(_ c: WithEntityID.Type) -> BuiltQuery<WithEntityID> {
        BuiltQuery(
            composite: Query<WithEntityID>(
                backstageComponents: [],
                excludedComponents: [],
                addedComponents: [],
                changedComponents: [],
                isQueryingForEntityID: true
            )
        )
    }

    public static func buildPartialBlock<each T>(first: BuiltQuery<repeat each T>) -> BuiltQuery<repeat each T> {
        first
    }

    public static func buildPartialBlock<each T, each U>(
        accumulated: BuiltQuery<repeat each T>,
        next: BuiltQuery<repeat each U>
    ) -> BuiltQuery<repeat each T, repeat each U> {
        BuiltQuery(
            composite:
                Query<repeat each T,repeat each U>(
                    backstageComponents:
                        accumulated.composite.backstageComponents.union(next.composite.backstageComponents),
                    excludedComponents:
                        accumulated.composite.excludedComponents.union(next.composite.excludedComponents),
                    addedComponents:
                        accumulated.composite.addedComponents.union(next.composite.addedComponents),
                    changedComponents:
                        accumulated.composite.changedComponents.union(next.composite.changedComponents),
                    isQueryingForEntityID: accumulated.composite.isQueryingForEntityID || next.composite.isQueryingForEntityID
                )
        )
    }
}

public extension Query {
    init(@QueryBuilder _ content: () -> BuiltQuery<repeat each T>) {
        let built = content()
        self = built.composite
    }
}
