public struct Entity {
    public struct ID: Hashable, Sendable {
        @inline(__always)
        public let slot: SlotIndex

        @inline(__always)
        public let generation: UInt32

        @inlinable @inline(__always)
        init(slot: SlotIndex, generation: UInt32) {
            self.slot = slot
            self.generation = generation
        }
    }
    public let id: ID
    public var signature = ComponentSignature()
}

public struct SlotIndex: RawRepresentable, Hashable, Comparable, Sendable, ExpressibleByIntegerLiteral {
    @inline(__always)
    public let rawValue: Array.Index

    @inlinable @inline(__always)
    public init(rawValue: Array.Index) {
        self.rawValue = rawValue
    }

    @inlinable @inline(__always)
    public init(integerLiteral value: Int) {
        self.rawValue = value
    }

    @inlinable @inline(__always)
    mutating func advancing() -> SlotIndex {
        SlotIndex(rawValue: rawValue + 1)
    }

    @inlinable @inline(__always)
    public static func < (lhs: SlotIndex, rhs: SlotIndex) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

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
