public struct Entity {
    public struct ID: Hashable, Sendable {
        public let slot: SlotIndex
        /*
         // TODO: I need this for a proper sparse set.
         //       I need some registry to track the current generation count and free IDs (after destroy).
         let rowIndex: Array.Index
         let generation: Int
         */

        @usableFromInline
        init(slot: SlotIndex) {
            self.slot = slot
        }
    }
    public let id: ID
    public var signature = ComponentSignature()
}

public struct SlotIndex: RawRepresentable, Hashable, Sendable, ExpressibleByIntegerLiteral {
    public let rawValue: Array.Index

    public init(rawValue: Array.Index) {
        self.rawValue = rawValue
    }

    public init(integerLiteral value: Int) {
        self.rawValue = value
    }

    mutating func advancing() -> SlotIndex {
        SlotIndex(rawValue: rawValue + 1)
    }
}

struct IndexRegistry {
    struct ArchetypeRow {
        let id: Int
        let row: Array.Index
    }

    enum ArchetypeLocation {
        case free
        case none
        case table(ArchetypeRow)
    }

    private(set) var archetype: [ArchetypeLocation] = [] // Indexed by `SlotIndex`
    private(set) var generation: [UInt32] = [] // Indexed by `SlotIndex`
    private(set) var freeIDs: ContiguousArray<SlotIndex> = []
    private(set) var nextID: SlotIndex = 0

    mutating func allocateID() -> Entity.ID {
        let newIndex = freeIDs.isEmpty ? popNextID() : freeIDs.removeFirst()

        let missingCount = (newIndex.rawValue + 1) - generation.count
        if missingCount > 0 {
            generation.append(contentsOf: repeatElement(0, count: missingCount))
        }
        if archetype.indices.contains(newIndex.rawValue) {
            archetype[newIndex.rawValue] = .free
        }
        self[generationFor: newIndex] += 1

        return Entity.ID(slot: newIndex)
    }

    mutating func free(id: Entity.ID) {
        freeIDs.append(id.slot)
        self[generationFor: id.slot] += 1
        if archetype.indices.contains(id.slot.rawValue) {
            archetype[id.slot.rawValue] = .free
        }
    }

    private mutating func popNextID() -> SlotIndex {
        let result = nextID
        nextID = nextID.advancing()
        return result
    }

    subscript(generationFor index: SlotIndex) -> UInt32 {
        _read {
            yield generation[index.rawValue]
        }
        _modify {
            yield &generation[index.rawValue]
        }
    }

    subscript(archetypeFor index: SlotIndex) -> ArchetypeLocation {
        _read {
            yield archetype[index.rawValue]
        }
        _modify {
            yield &archetype[index.rawValue]
        }
    }
}
