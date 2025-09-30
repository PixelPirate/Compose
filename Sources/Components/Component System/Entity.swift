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
