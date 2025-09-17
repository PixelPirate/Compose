struct Entity {
    struct ID: Hashable { let rawValue: Int }
    let id: ID
    var signature = ComponentSignature()
}
