@usableFromInline
struct IndexRegistry {
    @usableFromInline
    private(set) var generation: [UInt32] = [] // Indexed by `SlotIndex`

    @usableFromInline
    private(set) var freeIDs: Set<SlotIndex> = []

    @usableFromInline
    private(set) var nextID: SlotIndex = 0

    @inlinable @inline(__always)
    mutating func allocateID() -> Entity.ID {
        let newIndex = freeIDs.isEmpty ? popNextID() : freeIDs.removeFirst()

        let missingCount = (newIndex.rawValue + 1) - generation.count
        if missingCount > 0 {
            generation.append(contentsOf: repeatElement(0, count: missingCount))
        }
        self[generationFor: newIndex] += 1

        return Entity.ID(slot: newIndex, generation: generation[newIndex.rawValue])
    }

    @inlinable @inline(__always)
    var liveEntities: [Entity.ID] {
        (0..<nextID.rawValue) // TODO: Use `liveIDs`
            .lazy
            .filter { rawSlot in
                !freeIDs.contains(SlotIndex(rawValue: rawSlot))
            }
            .map { Entity.ID(slot: SlotIndex(rawValue: $0), generation: generation[$0]) }
    }

    @inlinable @inline(__always)
    var liveSlots: [SlotIndex] {
        (0..<nextID.rawValue) // TODO: Use `liveIDs`
            .lazy
            .filter { rawSlot in
                !freeIDs.contains(SlotIndex(rawValue: rawSlot))
            }
            .map { SlotIndex(rawValue: $0) }
    }

    @inlinable @inline(__always)
    mutating func free(id: Entity.ID) {
        freeIDs.insert(id.slot)
        self[generationFor: id.slot] += 1
    }

    @inlinable @inline(__always)
    internal mutating func popNextID() -> SlotIndex {
        let result = nextID
        nextID = nextID.advancing()
        return result
    }

    @inlinable @inline(__always)
    subscript(generationFor index: SlotIndex) -> UInt32 {
        @_transparent
        unsafeAddress {
            generation.withUnsafeBufferPointer { $0.baseAddress.unsafelyUnwrapped.advanced(by: index.rawValue) }
        }
        @_transparent
        unsafeMutableAddress {
            generation.withUnsafeMutableBufferPointer { $0.baseAddress.unsafelyUnwrapped.advanced(by: index.rawValue)}
        }
    }

    @inlinable @inline(__always)
    var generationView: SlotGenerationSpan {
        @inlinable @_transparent
        _read {
            yield SlotGenerationSpan(pointer: generation.withUnsafeBufferPointer { $0.baseAddress.unsafelyUnwrapped })
        }
    }
}

@usableFromInline
struct SlotGenerationSpan {
    @usableFromInline
    let pointer: UnsafePointer<UInt32>

    @inlinable @_transparent
    init(pointer: UnsafePointer<UInt32>) {
        self.pointer = pointer
    }

    @inlinable @inline(__always)
    subscript(_ index: SlotIndex) -> UInt32 {
        @inlinable @_transparent
        unsafeAddress {
            pointer.advanced(by: index.rawValue)
        }
    }
}
