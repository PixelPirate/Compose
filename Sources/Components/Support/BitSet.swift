#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

#if BITSET_USE_DYNAMIC_ARRAY
@usableFromInline typealias Word = UInt64
@usableFromInline typealias WordsStorage = ContiguousArray<Word>
@usableFromInline let wordMax: Int = 63
@usableFromInline let wordTop: Int = 64
@usableFromInline let wordShift: Int = 6
#else
@usableFromInline typealias Word = UInt128
@usableFromInline typealias WordsStorage = InlineArray<2, Word>
@usableFromInline let kInlineWordCapacity: Int = 2
@usableFromInline let wordMax: Int = 127
@usableFromInline let wordTop: Int = 128
@usableFromInline let wordShift: Int = 7
#endif

public struct BitSet: Hashable, Sendable {
    /// Reflects the highest set bit + 1.
    @usableFromInline @inline(__always)
    internal var bitCount: Int = 0

    @usableFromInline
    var words: BitStorage

    @inlinable @inline(__always)
    public static func == (lhs: BitSet, rhs: BitSet) -> Bool {
        lhs.isEqual(to: rhs)
    }

    @inlinable @inline(__always)
    public func hash(into hasher: inout Hasher) {
        for i in 0..<words.count {
            #if BITSET_USE_DYNAMIC_ARRAY
            hasher.combine(words[i])
            #else
            let lo = UInt64(truncatingIfNeeded: words[i])
            let hi = UInt64(truncatingIfNeeded: words[i] >> 64)
            hasher.combine(lo)
            hasher.combine(hi)
            #endif
        }
    }

    @inlinable @inline(__always)
    public init() {
        self.words = BitStorage()
        self.bitCount = 0
    }

    /// Optional capacity initializer: pre-allocates space for the given number of bits.
    @inlinable @inline(__always)
    public init(bitCount: Int) {
        precondition(bitCount >= 0)
        self.bitCount = 0
        let n = (bitCount + wordMax) >> wordShift
        self.words = BitStorage(repeating: 0, count: n)
    }

    @inlinable @inline(__always)
    public init(fullBitCount: Int) {
        precondition(fullBitCount >= 0)
        let n = (fullBitCount + wordMax) >> wordShift
        self.words = BitStorage(repeating: .max, count: n)
        self.bitCount = fullBitCount
        _maskTail()
    }

    @usableFromInline
    internal init(words: BitStorage, bitCount: Int) {
        self.words = words
        self.bitCount = bitCount
        self._maskTail()
    }

    @inlinable @inline(__always)
    public var isEmpty: Bool {
        bitCount == 0
    }

    @inlinable @inline(__always)
    public var numbers: AnyIterator<Int> {
        var wordIndex = 0
        var base = 0 // base bit index for the current word
        let words = self.words // capture a snapshot
        let wordCount = words.count
        let limit = self.bitCount // logical number of bits in use
        var currentWord: Word = 0
        return AnyIterator {
            while true {
                if currentWord != 0 {
                    // Extract the lowest set bit
                    let tz = currentWord.trailingZeroBitCount
                    let bit = base + tz
                    // Clear the extracted bit
                    currentWord &= currentWord &- 1
                    return bit
                }
                // Move to the next word
                if wordIndex >= wordCount { return nil }
                base = wordIndex << wordShift
                // If we've passed the logical limit, we're done
                if base >= limit { return nil }

                currentWord = words[wordIndex]
                wordIndex &+= 1

                // Mask off bits beyond `limit` in the (potential) last word
                let remaining = limit - base
                if remaining < wordTop {
                    if remaining <= 0 {
                        currentWord = 0
                    } else {
                        let mask: Word = (Word(1) &<< remaining) &- 1
                        currentWord &= mask
                    }
                }
                // Loop back to emit bits from currentWord (if any)
            }
        }
    }

    @inlinable @inline(__always)
    public func union(_ other: BitSet) -> BitSet {
        let maxWords = max(self.words.count, other.words.count)
        var newWords = BitStorage(repeating: 0, count: maxWords)
        for i in 0..<maxWords {
            let a: Word = i < self.words.count ? self.words[i] : 0
            let b: Word = i < other.words.count ? other.words[i] : 0
            newWords[i] = a | b
        }
        let maxBitCount = max(self.bitCount, other.bitCount)
        return BitSet(words: newWords, bitCount: maxBitCount)
    }

    @inlinable @inline(__always)
    public mutating func formUnion(_ other: BitSet) {
        let maxWords = max(self.words.count, other.words.count)
        let maxBitCount = max(self.bitCount, other.bitCount)
        words.ensureCapacity(requiredWords: maxWords)
        for i in 0..<maxWords {
            let a = i < self.words.count ? self.words[i] : 0
            let b = i < other.words.count ? other.words[i] : 0
            words[i] = a | b
        }
        bitCount = maxBitCount
    }

    @inlinable @inline(__always)
    public mutating func subtract(_ other: BitSet) {
        for i in 0..<words.count {
            let a = words[i]
            let b = i < other.words.count ? other.words[i] : 0
            words[i] = a & ~b
        }
        _shrinkToFitUsedBits()
    }

    /// Ensure capacity for a specific bit index (0-based). Grows storage.
    @usableFromInline @inline(__always)
    internal mutating func ensureCapacity(forBit bit: Int) {
        precondition(bit >= 0, "bit index must be non-negative")
        let requiredBits = bit &+ 1
        let requiredWords = (requiredBits + wordMax) >> wordShift
        words.ensureCapacity(requiredWords: requiredWords)
    }

    /// Call after any mutating change to keep a canonical tail (clears bits beyond bitCount in last word).
    @usableFromInline @inline(__always)
    internal mutating func _maskTail() {
        guard bitCount > 0, words.count > 0 else { return }
        let lastIdx = words.count - 1
        let bitsInLast = bitCount & wordMax
        if bitsInLast != 0 {
            let mask: Word = (Word(1) &<< bitsInLast) &- 1
            words[lastIdx] &= mask
        }
    }

    /// Shrinks trailing zero words and adjusts bitCount to highest set bit + 1.
    @usableFromInline @inline(__always)
    internal mutating func _shrinkToFitUsedBits() {
        if let (lastIdx, lastWord) = words.lastNonZeroWord() {
            let usedInLast = wordTop - lastWord.leadingZeroBitCount
            bitCount = lastIdx * wordTop + usedInLast
            words.trimToCount(lastIdx &+ 1)
        } else {
            bitCount = 0
            words.trimToCount(0)
        }
        _maskTail()
    }

    @inlinable @inline(__always)
    public mutating func insert(_ bit: Int) {
        ensureCapacity(forBit: bit)
        let wordIndex = bit >> wordShift
        let mask: Word = Word(1) &<< (bit & wordMax)
        words[wordIndex] |= mask
        let requiredBits = bit &+ 1
        bitCount = max(bitCount, requiredBits)
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
        let wordIndex = bit >> wordShift
        if wordIndex < words.count {
            let mask: Word = Word(1) &<< (bit & wordMax)
            words[wordIndex] &= ~mask
            if bit == bitCount - 1 {
                _shrinkToFitUsedBits()
            }
        }
        _maskTail()
    }

    @inlinable @inline(__always)
    public mutating func remove(_ bits: some Sequence<Int>) {
        for bit in bits { remove(bit) }
    }

    @inlinable @inline(__always)
    public func contains(_ bit: Int) -> Bool {
        guard bit >= 0 else { return false }
        if bit >= bitCount { return false }
        let wordIndex = bit >> wordShift
        if wordIndex < words.count {
            let mask: Word = Word(1) &<< (bit & wordMax)
            return words[wordIndex] & mask != 0
        }
        return false
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

@usableFromInline
struct BitStorage: Sendable {
    @usableFromInline var words: WordsStorage

    @inlinable @inline(__always)
    init() {
#if BITSET_USE_DYNAMIC_ARRAY
        self.words = []
#else
        self.words = WordsStorage(repeating: 0)
#endif
    }

    @inlinable @inline(__always)
    init(repeating value: Word, count: Int) {
#if BITSET_USE_DYNAMIC_ARRAY
        self.words = ContiguousArray(repeating: value, count: count)
#else
        precondition(count <= kInlineWordCapacity, "Inline storage has fixed capacity")
        self.words = WordsStorage { index in
            index < count ? value : 0
        }
#endif
    }

    @inlinable @inline(__always)
    var count: Int { words.count }

    @inlinable @inline(__always)
    subscript(_ index: Int) -> Word {
        get { words[index] }
        set { words[index] = newValue }
    }

    @inlinable @inline(__always)
    mutating func ensureCapacity(requiredWords: Int) {
#if BITSET_USE_DYNAMIC_ARRAY
        if requiredWords > words.count {
            words.append(contentsOf: repeatElement(0, count: requiredWords - words.count))
        }
#else
        precondition(requiredWords <= words.count, "Inline storage has fixed capacity; increase capacity or use dynamic array variant")
#endif
    }

    @inlinable @inline(__always)
    mutating func trimToCount(_ newCount: Int) {
#if BITSET_USE_DYNAMIC_ARRAY
        if newCount < words.count {
            words.removeSubrange(newCount..<words.count)
        }
#else
        // no-op for inline
#endif
    }

    @inlinable @inline(__always)
    func lastNonZeroWord() -> (index: Int, word: Word)? {
#if BITSET_USE_DYNAMIC_ARRAY
        var i = words.count - 1
        while i >= 0 {
            let w = words[i]
            if w != 0 { return (i, w) }
            if i == 0 { break }
            i &-= 1
        }
        return nil
#else
        var i = words.count - 1
        while i >= 0 {
            let w = words[i]
            if w != 0 { return (i, w) }
            if i == 0 { break }
            i &-= 1
        }
        return nil
#endif
    }
}
