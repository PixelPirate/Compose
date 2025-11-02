public struct QueryMetadata {
    public let readSignature: ComponentSignature
    public let writeSignature: ComponentSignature
    public let excludedSignature: ComponentSignature

    @inlinable @inline(__always)
    init(readSignature: ComponentSignature, writeSignature: ComponentSignature, excludedSignature: ComponentSignature) {
        self.readSignature = readSignature
        self.writeSignature = writeSignature
        self.excludedSignature = excludedSignature
    }
}

extension Query {
    /// Metadata used for scheduling. Includes optional components.
    @inlinable @inline(__always)
    public var schedulingMetadata: QueryMetadata {
        let readSignature = Self
            .makeReadSignature(backstageComponents: backstageComponents, includeOptionals: true)
            .appending(changeFilterSignature)
        return QueryMetadata(
            readSignature: readSignature,
            writeSignature: Self.makeWriteSignature(includeOptionals: true),
            excludedSignature: excludedSignature
        )
    }
}

public struct QueryHash: Hashable {
    let value: Int

    public init<each T: Component>(_ query: Query<repeat each T>) {
        var hasher = Hasher()
        hasher.combine(query.signature)
        hasher.combine(query.excludedSignature)
        self.value = hasher.finalize()
    }

    public init(include: ComponentSignature, exclude: ComponentSignature) {
        var hasher = Hasher()
        hasher.combine(include)
        hasher.combine(exclude)
        self.value = hasher.finalize()
    }
}

@usableFromInline
struct SparseQueryPlan {
    @usableFromInline
    let base: ContiguousArray<SlotIndex>
    @usableFromInline
    let others: [SlotsSpan<ContiguousArray.Index, SlotIndex>] // entityToComponents maps
    @usableFromInline
    let excluded: [SlotsSpan<ContiguousArray.Index, SlotIndex>]
    @usableFromInline
    let version: UInt64

    @usableFromInline
    init(
        base: ContiguousArray<SlotIndex>,
        others: [SlotsSpan<ContiguousArray.Index, SlotIndex>],
        excluded: [SlotsSpan<ContiguousArray.Index, SlotIndex>],
        version: UInt64
    ) {
        self.base = base
        self.others = others
        self.excluded = excluded
        self.version = version
    }
}

@usableFromInline
struct SignatureQueryPlan {
    @usableFromInline
    let base: ContiguousArray<SlotIndex>
    @usableFromInline
    let version: UInt64

    @usableFromInline
    init(
        base: ContiguousArray<SlotIndex>,
        version: UInt64
    ) {
        self.base = base
        self.version = version
    }
}

@usableFromInline
struct SlotsQueryPlan {
    @usableFromInline
    let base: ContiguousArray<SlotIndex>
    @usableFromInline
    let version: UInt64

    @usableFromInline
    init(
        base: ContiguousArray<SlotIndex>,
        version: UInt64
    ) {
        self.base = base
        self.version = version
    }
}
