/*
// This sadly can not work with the current version of Swift. Revisit when we support multiple type packs in type definitions.
protocol SystemParameter {
    static func insert(into: inout SystemMetadata)
    static func materialise(_ coordinator: Coordinator) -> Self
}
extension Query: SystemParameter {
    static func insert(into: inout SystemMetadata) {
        _ = Self.makeSignature(backstageComponents: [])
    }
    static func materialise(_ coordinator: Coordinator) -> Self {
        Query<repeat each T>(
            // Everything would have to be generic, this conflicts with the requirement of having a nicely typed output type pack.
            // Would need support for multiple type packs, see below.
            backstageComponents: [],
            excludedComponents: []
        )
    }
}
func receive<each P: SystemParameter>(_ fn: @escaping (repeat each P) -> Void) {
    var metadata: SystemMetadata!
    for p in repeat (each P).self {
        p.insert(into: &metadata)
    }
    let coordinator = Coordinator()
    let callIt = {
        fn(repeat (each P).materialise(coordinator))
    }
    callIt()
}
func test() {
    struct Transform: Component {
        static let componentTag = ComponentTag.makeTag()
    }
    func wow(_ query: Query<Write<Transform>>) {}
    receive(wow)
    // In order to synthesise a correct output type pack for the query, we need a new Swift feature where types can have multiple type packs.
    // e.g.:
    // struct Query<each Out, excluded: each Excluded> {}
    // Query<Write<Transform>, Person, excluded: PhysicsBody>
}
*/
