//
//  Query+Slots.swift
//  Components
//
//  Created by Patrick Horlebein on 12.10.25.
//

// TODO: Instead of fully rebuilding can we keep the cache up to date more efficiently?
extension Query {
    @usableFromInline @inline(__always)
    internal func getCachedArrays(_ coordinator: Coordinator)
    -> (base: ContiguousArray<SlotIndex>, others: [ContiguousArray<Array.Index?>], excluded: [ContiguousArray<Array.Index?>])
    {
        coordinator.sparseQueryCacheLock.lock()
        if
            let cached = coordinator.sparseQueryCache[hash],
            cached.version == coordinator.worldVersion
        {
            coordinator.sparseQueryCacheLock.unlock()
            return (
                cached.base,
                cached.others,
                cached.excluded
            )
        } else {
            coordinator.sparseQueryCacheLock.unlock()
            let new = coordinator.pool.baseAndOthers(
                repeat (each T).self,
                included: backstageComponents,
                excluded: excludedComponents
            )
            let newPlan = SparseQueryPlan(
                base: new.base,
                others: new.others,
                excluded: new.excluded,
                version: coordinator.worldVersion
            )
            coordinator.sparseQueryCacheLock.lock()
            coordinator.sparseQueryCache[hash] = newPlan
            coordinator.sparseQueryCacheLock.unlock()
            return new
        }
    }

    @usableFromInline @inline(__always)
    internal func getCachedBaseSlots(_ coordinator: Coordinator) -> ContiguousArray<SlotIndex> {
        coordinator.signatureQueryCacheLock.lock()
        if
            let cached = coordinator.signatureQueryCache[hash],
            cached.version == coordinator.worldVersion
        {
            coordinator.signatureQueryCacheLock.unlock()
            return cached.base
        } else {
            coordinator.signatureQueryCacheLock.unlock()
            let new = coordinator.pool.base(
                repeat (each T).self,
                included: backstageComponents
            )
            let newCache = SignatureQueryPlan(
                base: new,
                version: coordinator.worldVersion
            )
            coordinator.signatureQueryCacheLock.lock()
            coordinator.signatureQueryCache[hash] = newCache
            coordinator.signatureQueryCacheLock.unlock()
            return new
        }
    }

    @usableFromInline @inline(__always)
    internal func getCachedPreFilteredSlots(_ coordinator: Coordinator) -> ArraySlice<SlotIndex> {
        // If there is a group matching this query, then the slots are just the entities of the primary component
        let groupSignature = GroupSignature(querySignature)
        if let slots = coordinator.groupSlots(groupSignature) {
            return slots
        }

        coordinator.slotsQueryCacheLock.lock()
        if
            let cached = coordinator.slotsQueryCache[hash],
            cached.version == coordinator.worldVersion
        {
            coordinator.slotsQueryCacheLock.unlock()
            return cached.base[...]
        } else {
            coordinator.slotsQueryCacheLock.unlock()
            let new = coordinator.pool.slots(
                repeat (each T).self,
                included: backstageComponents,
                excluded: excludedComponents
            )
            let newCache = SlotsQueryPlan(
                base: new,
                version: coordinator.worldVersion
            )
            coordinator.slotsQueryCacheLock.lock()
            coordinator.slotsQueryCache[hash] = newCache
            coordinator.slotsQueryCacheLock.unlock()
            return new[...]
        }
    }
}
