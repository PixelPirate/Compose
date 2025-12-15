import Foundation

public struct ComponentTicks: Sendable {
    @usableFromInline
    internal var added: UInt64
    @usableFromInline
    internal var changed: UInt64
    @usableFromInline
    internal var removed: UInt64

    @inlinable @inline(__always)
    init(tick: UInt64) {
        self.added = tick
        self.changed = tick
        self.removed = .min
    }

    @inlinable @inline(__always)
    init(added: UInt64, changed: UInt64) {
        self.added = added
        self.changed = changed
        self.removed = .min
    }

    @inlinable @inline(__always)
    init(added: UInt64, changed: UInt64, removed: UInt64) {
        self.added = added
        self.changed = changed
        self.removed = removed
    }

    @usableFromInline
    static let never = ComponentTicks(added: .min, changed: .min, removed: .min)

    @inlinable @inline(__always)
    mutating func markAdded(at tick: UInt64) {
        added = tick
        changed = tick
    }

    @inlinable @inline(__always)
    mutating func markChanged(at tick: UInt64) {
        changed = tick
    }

    @inlinable @inline(__always)
    mutating func markRemoved(at tick: UInt64) {
        removed = tick
    }

    @inlinable @inline(__always) @_transparent
    func isAdded(since lastRun: UInt64, upTo currentRun: UInt64) -> Bool {
        added > lastRun && added <= currentRun
    }

    @inlinable @inline(__always) @_transparent
    func isChanged(since lastRun: UInt64, upTo currentRun: UInt64) -> Bool {
        changed > lastRun && changed <= currentRun
    }

    @inlinable @inline(__always) @_transparent
    func isRemoved(since lastRun: UInt64, upTo currentRun: UInt64) -> Bool {
        removed > lastRun && removed <= currentRun
    }
}
