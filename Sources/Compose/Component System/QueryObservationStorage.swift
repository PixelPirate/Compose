import Foundation

/// Generation-aware dense storage for observed query results.
///
/// Maintains two parallel dense arrays — entity identifiers and resolved elements — plus a
/// sparse slot→dense index for O(1) per-entity lookup. Generation checks on every operation
/// prevent slot-reuse bugs.
///
/// ## Ordering
///
/// `fullResync` populates in query-emitted order. `upsert` appends to the end. `remove` uses
/// swap-remove: the gap is filled with the last row, preserving order modulo the gap-fill.
///
/// ## Thread safety
///
/// No internal synchronization. Writes happen in the single-threaded `.perceptionObservation`
/// schedule. Reads happen via `observe(_:)` on the UI actor and must not overlap with writes.
@usableFromInline
final class QueryObservationStorage<each T: ComponentResolving>: @unchecked Sendable {
    /// The public result element type exposed to observers.
    @usableFromInline
    typealias Element = (repeat (each T).ReadOnlyResolvedType)

    /// Parallel dense arrays: `entityIDs[i]` and `elements[i]` form row `i`.
    @usableFromInline
    var entityIDs: ContiguousArray<Entity.ID>

    @usableFromInline
    var elements: ContiguousArray<Element>

    /// Maps each `SlotIndex` to its position in the dense arrays, or `.notFound` if absent.
    @usableFromInline
    private(set) var slotToDense: SparseArray<ContiguousArray.Index, SlotIndex>

    /// Monotonically increasing version bumped on every structural mutation.
    @usableFromInline
    private(set) var storageVersion: UInt64

    @usableFromInline
    init() {
        self.entityIDs = []
        self.elements = []
        self.slotToDense = SparseArray()
        self.storageVersion = 0
    }

    deinit {
        slotToDense.deallocate()
    }

    @usableFromInline
    var count: Int { entityIDs.count }

    @usableFromInline
    var isEmpty: Bool { entityIDs.isEmpty }

    // MARK: - Queries

    /// Returns `true` iff the entity exists in storage with a matching generation.
    @usableFromInline
    func contains(_ entityID: Entity.ID) -> Bool {
        let denseIndex = slotToDense[entityID.slot]
        guard denseIndex != .notFound else { return false }
        return entityIDs[denseIndex].generation == entityID.generation
    }

    /// Returns the entity ID at the given dense index.
    @usableFromInline
    func entityID(at index: Int) -> Entity.ID {
        entityIDs[index]
    }

    /// Returns the element at the given dense index.
    @inlinable @inline(__always)
    func element(at index: Int) -> Element {
        elements[index]
    }

    // MARK: - Mutations

    /// Inserts a new row or replaces an existing row for the same entity generation.
    ///
    /// If the slot holds a row with a **different** generation (stale entry from a destroyed
    /// entity), the stale row is evicted before appending the new one.
    @usableFromInline
    func upsert(_ entityID: Entity.ID, element: Element) {
        let denseIndex = slotToDense[entityID.slot]

        if denseIndex != .notFound {
            if entityIDs[denseIndex].generation == entityID.generation {
                entityIDs[denseIndex] = entityID
                elements[denseIndex] = element
                storageVersion &+= 1
                return
            }
            // Stale row from a previous generation — evict it first.
            _removeAt(denseIndex)
        }

        slotToDense.ensureCapacity(forIndex: entityID.slot)
        entityIDs.append(entityID)
        elements.append(element)
        slotToDense[entityID.slot] = count - 1
        storageVersion &+= 1
    }

    /// Removes the row for `entityID` if it exists and the generation matches.
    /// Uses swap-remove for O(1) amortized.
    @usableFromInline
    func remove(_ entityID: Entity.ID) {
        let denseIndex = slotToDense[entityID.slot]
        guard denseIndex != .notFound, entityIDs[denseIndex].generation == entityID.generation else {
            return
        }
        _removeAt(denseIndex)
    }

    /// Drop all rows and reset the sparse mapping.
    @usableFromInline
    func removeAll(keepingCapacity: Bool = false) {
        entityIDs.removeAll(keepingCapacity: keepingCapacity)
        elements.removeAll(keepingCapacity: keepingCapacity)
        slotToDense = SparseArray()
        storageVersion &+= 1
    }

    /// Replaces the entire storage with rows from the given sequence, preserving insertion order.
    @usableFromInline
    func fullResync(from rows: some Sequence<(Entity.ID, Element)>) {
        entityIDs.removeAll(keepingCapacity: true)
        elements.removeAll(keepingCapacity: true)
        slotToDense = SparseArray()

        for (entityID, element) in rows {
            slotToDense.ensureCapacity(forIndex: entityID.slot)
            entityIDs.append(entityID)
            elements.append(element)
            slotToDense[entityID.slot] = count - 1
        }

        storageVersion &+= 1
    }

    // MARK: - PerceptibleQuery bridge

    @usableFromInline
    func pqSync(_ ids: [Entity.ID], _ all: [Element]) {
        guard !ids.isEmpty else { return }
        fullResync(from: zip(ids, all))
    }

    // MARK: - Internal

    @usableFromInline
    func _removeAt(_ index: Int) {
        let lastIndex = count - 1
        let removedSlot = entityIDs[index].slot

        if index != lastIndex {
            let lastEntitySlot = entityIDs[lastIndex].slot
            entityIDs[index] = entityIDs[lastIndex]
            elements[index] = elements[lastIndex]
            slotToDense[lastEntitySlot] = index
        }

        slotToDense[removedSlot] = .notFound
        entityIDs.removeLast()
        elements.removeLast()
        storageVersion &+= 1
    }
}