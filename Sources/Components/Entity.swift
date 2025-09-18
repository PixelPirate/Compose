struct Entity {
    struct ID: Hashable {
        typealias Index = Int
        let rawValue: Index
        /*
         // TODO: I need this for a proper sparse set.
         //       I need some registry to track the current generation count and free IDs (after destroy).
         let rowIndex: Array.Index
         let generation: Int
         */
    }
    let id: ID
    var signature = ComponentSignature()
}

typealias SlotIndex = Int

struct ArchetypeRegistry {
    struct ArchetypeRow {
        let id: Int
        let row: Array.Index
    }

    enum ArchetypeLocation {
        case free
        case none
        case table(ArchetypeRow)
    }

    private var archetype: [ArchetypeLocation] = [] // Indexed by `SlotIndex`
    private var slot: [Entity.ID.Index: SlotIndex] = [:]
    private var generation: [Int] = [] // Indexed by `SlotIndex`

    subscript(generationFor index: Entity.ID.Index) -> Int {
        _read {
            let slotIndex = slot[index]!
            yield generation[slotIndex]
        }
        _modify {
            let slotIndex = slot[index]!
            yield &generation[slotIndex]
        }
    }

    subscript(archetypeFor index: Entity.ID.Index) -> ArchetypeLocation {
        _read {
            let slotIndex = slot[index]!
            yield archetype[slotIndex]
        }
        _modify {
            let slotIndex = slot[index]!
            yield &archetype[slotIndex]
        }
    }
}
