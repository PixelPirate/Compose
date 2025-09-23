//
//  BitSet.swift
//  Components
//
//  Created by Patrick Horlebein (extern) on 23.09.25.
//

#if canImport(Darwin)
import Darwin // for memcmp
#else
import Glibc  // Linux
#endif

public struct BitSet: Hashable {
    /// Reflects the highest set bit + 1.
    @usableFromInline @inline(__always)
    internal var bitCount: Int = 0
    @usableFromInline var words: ContiguousArray<UInt64>

    @inlinable @inline(__always)
    public static func == (lhs: BitSet, rhs: BitSet) -> Bool {
        lhs.isEqual(to: rhs)
    }

    @inlinable @inline(__always)
    public func hash(into hasher: inout Hasher) {
        // `words` is always updated when inserting/removing, so currently there cannot be the case where
        // a BitSet has a leading zero word.
        hasher.combine(words)
    }

    @inlinable @inline(__always)
    public init() {
        self.words = []
        self.bitCount = 0
    }

    /// Optional capacity initializer: pre-allocates space for the given number of bits.
    @inlinable @inline(__always)
    public init(bitCount: Int) {
        precondition(bitCount >= 0)
        self.bitCount = 0 // actual used range starts at 0; we only grow when bits are set
        let n = (bitCount + 63) >> 6
        self.words = ContiguousArray(repeating: 0, count: n)
    }

    /// Ensure capacity for a specific bit index (0-based). Grows storage.
    @usableFromInline @inline(__always)
    internal mutating func ensureCapacity(forBit bit: Int) {
        precondition(bit >= 0, "bit index must be non-negative")
        let requiredBits = bit &+ 1
        let requiredWords = (requiredBits + 63) >> 6
        if requiredWords > words.count {
            words.append(contentsOf: repeatElement(0, count: requiredWords - words.count))
        }
        if requiredBits > bitCount { bitCount = requiredBits }
    }

    /// Call after any mutating change to keep a canonical tail (clears bits beyond bitCount in last word).
    @usableFromInline @inline(__always)
    internal mutating func _maskTail() {
        guard bitCount > 0, let lastIdx = words.indices.last else { return }
        let bitsInLast = bitCount & 63
        if bitsInLast != 0 {
            let mask: UInt64 = bitsInLast == 64 ? ~0 : ((1 &<< bitsInLast) &- 1)
            words[lastIdx] &= mask
        }
    }

    /// Shrinks trailing zero words and adjusts bitCount to highest set bit + 1.
    @usableFromInline @inline(__always)
    internal mutating func _shrinkToFitUsedBits() {
        // Drop trailing zero words
        while let last = words.last, last == 0 { words.removeLast() }
        if let last = words.last {
            let lastIdx = words.count - 1
            // Highest set bit position in last word
            let usedInLast = 64 - last.leadingZeroBitCount
            bitCount = lastIdx * 64 + usedInLast
        } else {
            bitCount = 0
        }
        _maskTail()
    }

    @inlinable @inline(__always)
    public mutating func insert(_ bit: Int) {
        ensureCapacity(forBit: bit)
        let wordIndex = bit >> 6
        let mask: UInt64 = 1 &<< (bit & 63)
        words[wordIndex] |= mask
        let requiredBits = bit &+ 1
        if requiredBits > bitCount { bitCount = requiredBits }
        _maskTail()
    }

    @inlinable @inline(__always)
    public mutating func insert(_ bits: Int...) {
        for bit in bits { insert(bit) }
    }

    @inlinable @inline(__always)
    public mutating func insert(_ bits: some Sequence<Int>) {
        for bit in bits { insert(bit) }
    }

    @inlinable @inline(__always)
    public mutating func remove(_ bit: Int) {
        guard bit >= 0 else { return }
        if bit >= bitCount { return }
        let wordIndex = bit >> 6
        if wordIndex < words.count {
            let mask: UInt64 = 1 &<< (bit & 63)
            words[wordIndex] &= ~mask
            if bit == bitCount - 1 {
                _shrinkToFitUsedBits()
            }
        }
        _maskTail()
    }

    @inlinable @inline(__always)
    public func isEqual(to other: BitSet) -> Bool {
        let maxCount = max(self.words.count, other.words.count)
        var i = 0
        while i < maxCount {
            let a = i < self.words.count ? self.words[i] : 0
            let b = i < other.words.count ? other.words[i] : 0
            if a != b { return false }
            i &+= 1
        }
        return true
    }

    @inlinable @inline(__always)
    public func isSuperset(of sup: BitSet) -> Bool {
        sup.isSubset(of: self)
    }

    @inlinable @inline(__always)
    public func isSuperset(of sup: BitSet, isDisjoint dis: BitSet) -> Bool {
        let maxCount = max(sup.words.count, self.words.count, dis.words.count)
        var i = 0
        while i < maxCount {
            let a = i < sup.words.count ? sup.words[i] : 0
            let b = i < self.words.count ? self.words[i] : 0
            guard (a & ~b) == 0 else { return false }

            let d = i < dis.words.count ? dis.words[i] : 0
            if (b & d) != 0 { return false }

            i &+= 1
        }
        return true
    }

    @inlinable @inline(__always)
    public func isSubset(of sup: BitSet) -> Bool {
        // Treat missing higher words as zeros on either side.
        let maxCount = max(self.words.count, sup.words.count)
        var i = 0
        while i < maxCount {
            let a = i < self.words.count ? self.words[i] : 0
            let b = i < sup.words.count ? sup.words[i] : 0
            guard (a & ~b) == 0 else { return false }
            i &+= 1
        }
        return true
    }

    @inlinable @inline(__always)
    public func isDisjoint(with other: BitSet) -> Bool {
        let maxCount = max(self.words.count, other.words.count)
        var i = 0
        while i < maxCount {
            let a = i < self.words.count ? self.words[i] : 0
            let b = i < other.words.count ? other.words[i] : 0
            if (a & b) != 0 { return false }
            i &+= 1
        }
        return true
    }
}
