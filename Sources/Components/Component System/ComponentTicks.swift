import Foundation

public struct ComponentTicks: Sendable {
    @usableFromInline
    internal var added: UInt64
    @usableFromInline
    internal var changed: UInt64

    @inlinable @inline(__always)
    init(tick: UInt64) {
        self.added = tick
        self.changed = tick
    }

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
    func isAdded(since lastRun: UInt64, upTo currentRun: UInt64) -> Bool {
        added > lastRun && added <= currentRun
    }

    @inlinable @inline(__always)
    func isChanged(since lastRun: UInt64, upTo currentRun: UInt64) -> Bool {
        changed > lastRun && changed <= currentRun
    }
}
