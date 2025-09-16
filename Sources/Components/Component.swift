import BitCollections
import Atomics

protocol Component: ComponentResolving {
    static var componentTag: ComponentTag { get }
}

struct ComponentSignature: Hashable {
    var rawHashValue: BitSet

    private init(raw: BitSet) {
        rawHashValue = raw
    }

    init(_ tags: ComponentTag...) {
        rawHashValue = tags.reduce(into: BitSet()) { bitSet, tag in
            bitSet.insert(tag.rawValue)
        }
    }

    func appending(_ tag: ComponentTag) -> Self {
        var newSignature = rawHashValue
        newSignature.insert(tag.rawValue)
        return ComponentSignature(raw: newSignature)
    }
}

struct ComponentTag: Hashable {
    let rawValue: Int

    nonisolated(unsafe) private static var nextTag: UnsafeAtomic<Int> = .create(0)

    static func makeTag() -> Self {
        ComponentTag(
            rawValue: Self.nextTag.loadThenWrappingIncrement(ordering: .sequentiallyConsistent)
        )
    }
}
