import Atomics
import os

@usableFromInline
final class ChangeClock: @unchecked Sendable {
    @usableFromInline
    let value: ManagedAtomic<UInt64> = ManagedAtomic(0)

    @inlinable @inline(__always)
    func next() -> UInt64 {
        value.wrappingIncrementThenLoad(ordering: .sequentiallyConsistent)
    }

    @inlinable @inline(__always)
    func current() -> UInt64 {
        value.load(ordering: .relaxed)
    }
}

@usableFromInline
final class ComponentChangeState: @unchecked Sendable {
    @usableFromInline
    var added: ContiguousArray<UInt64> = []
    @usableFromInline
    var changed: ContiguousArray<UInt64> = []
    @usableFromInline
    let lock = OSAllocatedUnfairLock()

    @inlinable @inline(__always)
    func ensureCapacity(for index: Int) {
        if index >= added.count {
            let newCount = index + 1
            let additional = newCount - added.count
            added.append(contentsOf: repeatElement(0, count: additional))
            changed.append(contentsOf: repeatElement(0, count: additional))
        }
    }

    @inlinable @inline(__always)
    func markAdded(slot: SlotIndex, tick: UInt64) {
        lock.lock()
        ensureCapacity(for: slot.rawValue)
        added[slot.rawValue] = tick
        changed[slot.rawValue] = tick
        lock.unlock()
    }

    @inlinable @inline(__always)
    func markChanged(slot: SlotIndex, tick: UInt64) {
        lock.lock()
        ensureCapacity(for: slot.rawValue)
        changed[slot.rawValue] = tick
        lock.unlock()
    }

    @inlinable @inline(__always)
    func clear(slot: SlotIndex) {
        lock.lock()
        guard slot.rawValue < added.count else {
            lock.unlock()
            return
        }
        added[slot.rawValue] = 0
        changed[slot.rawValue] = 0
        lock.unlock()
    }

    @inlinable @inline(__always)
    func lastAdded(slot: SlotIndex) -> UInt64 {
        lock.lock()
        let value = slot.rawValue < added.count ? added[slot.rawValue] : 0
        lock.unlock()
        return value
    }

    @inlinable @inline(__always)
    func lastChanged(slot: SlotIndex) -> UInt64 {
        lock.lock()
        let value = slot.rawValue < changed.count ? changed[slot.rawValue] : 0
        lock.unlock()
        return value
    }
}

@usableFromInline
struct ComponentChangeObserverContext: @unchecked Sendable {
    @usableFromInline let state: ComponentChangeState
    @usableFromInline let clock: ChangeClock

    @inlinable @inline(__always)
    func observer(for entityID: Entity.ID) -> ComponentChangeObserver {
        ComponentChangeObserver(state: state, clock: clock, slot: entityID.slot)
    }
}

@usableFromInline
struct ComponentChangeObserver: @unchecked Sendable {
    @usableFromInline let state: ComponentChangeState
    @usableFromInline let clock: ChangeClock
    @usableFromInline let slot: SlotIndex

    @usableFromInline
    init(state: ComponentChangeState, clock: ChangeClock, slot: SlotIndex) {
        self.state = state
        self.clock = clock
        self.slot = slot
    }

    @inlinable @inline(__always)
    func markChanged() {
        let tick = clock.next()
        state.markChanged(slot: slot, tick: tick)
    }
}

extension Coordinator {
    @inlinable @inline(__always)
    func currentChangeTick() -> UInt64 {
        changeClock.current()
    }

    @usableFromInline @inline(__always)
    func changeState(for tag: ComponentTag) -> ComponentChangeState {
        componentChangeLock.lock()
        if let existing = componentChanges[tag] {
            componentChangeLock.unlock()
            return existing
        }
        let state = ComponentChangeState()
        componentChanges[tag] = state
        componentChangeLock.unlock()
        return state
    }

    @usableFromInline @inline(__always)
    func changeStateIfExists(for tag: ComponentTag) -> ComponentChangeState? {
        componentChangeLock.lock()
        let state = componentChanges[tag]
        componentChangeLock.unlock()
        return state
    }

    @usableFromInline @inline(__always)
    func markComponentAdded(_ tag: ComponentTag, to entityID: Entity.ID) {
        let tick = changeClock.next()
        changeState(for: tag).markAdded(slot: entityID.slot, tick: tick)
    }

    @usableFromInline @inline(__always)
    func markComponentChanged(_ tag: ComponentTag, on entityID: Entity.ID) {
        let tick = changeClock.next()
        changeState(for: tag).markChanged(slot: entityID.slot, tick: tick)
    }

    @usableFromInline @inline(__always)
    func clearComponentTracking(_ tag: ComponentTag, entityID: Entity.ID) {
        changeStateIfExists(for: tag)?.clear(slot: entityID.slot)
    }

    @usableFromInline @inline(__always)
    func lastAddedTick(for tag: ComponentTag, slot: SlotIndex) -> UInt64 {
        changeStateIfExists(for: tag)?.lastAdded(slot: slot) ?? 0
    }

    @usableFromInline @inline(__always)
    func lastChangedTick(for tag: ComponentTag, slot: SlotIndex) -> UInt64 {
        changeStateIfExists(for: tag)?.lastChanged(slot: slot) ?? 0
    }

    @usableFromInline @inline(__always)
    func observerContext(for tag: ComponentTag) -> ComponentChangeObserverContext {
        ComponentChangeObserverContext(state: changeState(for: tag), clock: changeClock)
    }

    @usableFromInline @inline(__always)
    func lastRunTick(of systemID: SystemID) -> UInt64 {
        systemTickLock.lock()
        let tick = systemLastRunTicks[systemID] ?? 0
        systemTickLock.unlock()
        return tick
    }

    @usableFromInline @inline(__always)
    func setLastRunTick(_ tick: UInt64, for systemID: SystemID) {
        systemTickLock.lock()
        systemLastRunTicks[systemID] = tick
        systemTickLock.unlock()
    }

    @usableFromInline @inline(__always)
    func registerSystemTick(_ systemID: SystemID) {
        systemTickLock.lock()
        systemLastRunTicks[systemID] = systemLastRunTicks[systemID] ?? 0
        systemTickLock.unlock()
    }

    @usableFromInline @inline(__always)
    func unregisterSystemTick(_ systemID: SystemID) {
        systemTickLock.lock()
        systemLastRunTicks.removeValue(forKey: systemID)
        systemTickLock.unlock()
    }
}
