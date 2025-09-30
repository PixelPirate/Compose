@usableFromInline
struct IndexRegistry {
    @usableFromInline
    struct ArchetypeRow {
        let id: Int
        let row: Array.Index
    }

    @usableFromInline
    enum ArchetypeLocation {
        case free
        case none
        case table(ArchetypeRow)
    }

    @usableFromInline
    private(set) var archetype: [ArchetypeLocation] = [] // Indexed by `SlotIndex`

    @usableFromInline
    private(set) var generation: [UInt32] = [] // Indexed by `SlotIndex`

    @usableFromInline
    private(set) var freeIDs: ContiguousArray<SlotIndex> = []

    @usableFromInline
    private(set) var nextID: SlotIndex = 0

    @inlinable @inline(__always)
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

        return Entity.ID(slot: newIndex, generation: generation[newIndex.rawValue])
    }

    @inlinable @inline(__always)
    var liveEntities: [Entity.ID] {
        (0..<nextID.rawValue)
            .map { Entity.ID(slot: SlotIndex(rawValue: $0), generation: 0) }
            .filter { id in
                !freeIDs.lazy.map(\.rawValue).contains(id.slot.rawValue)
            }
    }

    @inlinable @inline(__always)
    mutating func free(id: Entity.ID) {
        freeIDs.append(id.slot)
        self[generationFor: id.slot] += 1
        if archetype.indices.contains(id.slot.rawValue) {
            archetype[id.slot.rawValue] = .free
        }
    }

    @inlinable @inline(__always)
    internal mutating func popNextID() -> SlotIndex {
        let result = nextID
        nextID = nextID.advancing()
        return result
    }

    @inlinable @inline(__always)
    subscript(generationFor index: SlotIndex) -> UInt32 {
        _read {
            yield generation[index.rawValue]
        }
        _modify {
            yield &generation[index.rawValue]
        }
    }

    @usableFromInline @inline(__always)
    subscript(archetypeFor index: SlotIndex) -> ArchetypeLocation {
        _read {
            yield archetype[index.rawValue]
        }
        _modify {
            yield &archetype[index.rawValue]
        }
    }
}
