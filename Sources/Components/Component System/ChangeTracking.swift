import Atomics
import os

@usableFromInline
typealias ChangeTick = UInt32

@usableFromInline
let maxChangeTickAge: ChangeTick = ChangeTick.max / 2

@inlinable @inline(__always)
func clampTickAge(_ tick: ChangeTick, relativeTo current: ChangeTick) -> ChangeTick {
    let age = current &- tick
    if age > maxChangeTickAge {
        return current &- maxChangeTickAge
    }
    return tick
}

@inlinable @inline(__always)
func isTickNewer(_ tick: ChangeTick, than lastRun: ChangeTick, relativeTo current: ChangeTick) -> Bool {
    guard tick != 0 else { return false }
    let tickAge = current &- tick
    if tickAge > maxChangeTickAge {
        return false
    }
    let lastAge = current &- lastRun
    return tickAge < lastAge
}

@usableFromInline
final class ChangeClock: @unchecked Sendable {
    @usableFromInline
    let value: ManagedAtomic<ChangeTick> = ManagedAtomic(0)

    @inlinable @inline(__always)
    func next() -> ChangeTick {
        var next = value.wrappingIncrementThenLoad(ordering: .sequentiallyConsistent)
        if next == 0 {
            next = value.wrappingIncrementThenLoad(ordering: .sequentiallyConsistent)
        }
        return next
    }

    @inlinable @inline(__always)
    func current() -> ChangeTick {
        value.load(ordering: .relaxed)
    }
}

@usableFromInline
struct AtomicComponentTicks: Sendable {
    @usableFromInline
    let storage: ManagedAtomic<UInt64>

    @inlinable @inline(__always)
    init() {
        storage = ManagedAtomic(0)
    }

    @usableFromInline @inline(__always)
    static func pack(added: ChangeTick, changed: ChangeTick) -> UInt64 {
        (UInt64(added) << 32) | UInt64(changed)
    }

    @usableFromInline @inline(__always)
    static func unpackAdded(_ value: UInt64) -> ChangeTick {
        ChangeTick(value >> 32)
    }

    @usableFromInline @inline(__always)
    static func unpackChanged(_ value: UInt64) -> ChangeTick {
        ChangeTick(truncatingIfNeeded: value)
    }

    @inlinable @inline(__always)
    func store(added: ChangeTick, changed: ChangeTick) {
        storage.store(Self.pack(added: added, changed: changed), ordering: .relaxed)
    }

    @inlinable @inline(__always)
    func storeChanged(_ tick: ChangeTick) {
        while true {
            let current = storage.load(ordering: .relaxed)
            let newValue = (current & ~UInt64(UInt32.max)) | UInt64(tick)
            let exchange = storage.compareExchange(
                expected: current,
                desired: newValue,
                ordering: .relaxed
            )
            if exchange.exchanged {
                return
            }
        }
    }

    @inlinable @inline(__always)
    func clear() {
        storage.store(0, ordering: .relaxed)
    }

    @inlinable @inline(__always)
    func lastAdded() -> ChangeTick {
        Self.unpackAdded(storage.load(ordering: .relaxed))
    }

    @inlinable @inline(__always)
    func lastChanged() -> ChangeTick {
        Self.unpackChanged(storage.load(ordering: .relaxed))
    }
}

@usableFromInline
final class ComponentChangeState: @unchecked Sendable {
    @usableFromInline
    var ticks: ContiguousArray<AtomicComponentTicks> = []
    @usableFromInline
    let lock = OSAllocatedUnfairLock()

    @inlinable @inline(__always)
    func ensureCapacity(for index: Int) {
        if index >= ticks.count {
            lock.lock()
            if index >= ticks.count {
                var appended = ticks.count
                while appended <= index {
                    ticks.append(AtomicComponentTicks())
                    appended &+= 1
                }
            }
            lock.unlock()
        }
    }

    @inlinable @inline(__always)
    func markAdded(slot: SlotIndex, tick: ChangeTick) {
        ensureCapacity(for: slot.rawValue)
        ticks[slot.rawValue].store(added: tick, changed: tick)
    }

    @inlinable @inline(__always)
    func markChanged(slot: SlotIndex, tick: ChangeTick) {
        ensureCapacity(for: slot.rawValue)
        ticks[slot.rawValue].storeChanged(tick)
    }

    @inlinable @inline(__always)
    func clear(slot: SlotIndex) {
        lock.lock()
        guard slot.rawValue < ticks.count else {
            lock.unlock()
            return
        }
        ticks[slot.rawValue].clear()
        lock.unlock()
    }

    @inlinable @inline(__always)
    func lastAdded(slot: SlotIndex) -> ChangeTick {
        guard slot.rawValue < ticks.count else { return 0 }
        return ticks[slot.rawValue].lastAdded()
    }

    @inlinable @inline(__always)
    func lastChanged(slot: SlotIndex) -> ChangeTick {
        guard slot.rawValue < ticks.count else { return 0 }
        return ticks[slot.rawValue].lastChanged()
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
    func currentChangeTick() -> ChangeTick {
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
    func lastAddedTick(for tag: ComponentTag, slot: SlotIndex) -> ChangeTick {
        changeStateIfExists(for: tag)?.lastAdded(slot: slot) ?? 0
    }

    @usableFromInline @inline(__always)
    func lastChangedTick(for tag: ComponentTag, slot: SlotIndex) -> ChangeTick {
        changeStateIfExists(for: tag)?.lastChanged(slot: slot) ?? 0
    }

    @usableFromInline @inline(__always)
    func observerContext(for tag: ComponentTag) -> ComponentChangeObserverContext {
        ComponentChangeObserverContext(state: changeState(for: tag), clock: changeClock)
    }

    @usableFromInline @inline(__always)
    func lastRunTick(of systemID: SystemID) -> ChangeTick {
        systemTickLock.lock()
        let tick = systemLastRunTicks[systemID] ?? 0
        systemTickLock.unlock()
        return clampTickAge(tick, relativeTo: changeClock.current())
    }

    @usableFromInline @inline(__always)
    func setLastRunTick(_ tick: ChangeTick, for systemID: SystemID) {
        let sanitized = clampTickAge(tick, relativeTo: changeClock.current())
        systemTickLock.lock()
        systemLastRunTicks[systemID] = sanitized
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
