//
//  Query+Plan.swift
//  Components
//
//  Created by Patrick Horlebein (extern) on 10.10.25.
//

public struct QueryMetadata {
    public let signature: ComponentSignature
    public let readSignature: ComponentSignature
    public let writeSignature: ComponentSignature
    public let excludedSignature: ComponentSignature

    @inlinable @inline(__always)
    init(signature: ComponentSignature, readSignature: ComponentSignature, writeSignature: ComponentSignature, excludedSignature: ComponentSignature) {
        self.signature = signature
        self.readSignature = readSignature
        self.writeSignature = writeSignature
        self.excludedSignature = excludedSignature
    }
}

extension Query {
    @inlinable @inline(__always)
    public var metadata: QueryMetadata {
        QueryMetadata(
            signature: signature,
            readSignature: readOnlySignature,
            writeSignature: writeSignature,
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
    let others: [ContiguousArray<Array.Index?>] // entityToComponents maps
    @usableFromInline
    let excluded: [ContiguousArray<Array.Index?>]
    @usableFromInline
    let version: UInt64

    @usableFromInline
    init(
        base: ContiguousArray<SlotIndex>,
        others: [ContiguousArray<Array.Index?>],
        excluded: [ContiguousArray<Array.Index?>],
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
