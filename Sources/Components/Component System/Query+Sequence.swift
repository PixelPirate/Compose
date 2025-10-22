//
//  Query+Sequence.swift
//  Components
//
//  Created by Patrick Horlebein (extern) on 10.10.25.
//

public struct LazyQuerySequence<each T: ComponentResolving>: Sequence {
    @usableFromInline
    internal let entityIDs: [Entity.ID]

    @usableFromInline
    internal let accessors: (repeat TypedAccess<each T>)

    @inlinable @inline(__always)
    init(entityIDs: [Entity.ID], accessors: repeat TypedAccess<each T>) {
        self.entityIDs = entityIDs
        self.accessors = (repeat each accessors)
    }

    @inlinable @inline(__always)
    public func makeIterator() -> AnyIterator<(repeat (each T).ReadOnlyResolvedType)> {
        var index = 0
        return AnyIterator {
            guard index < entityIDs.count else { return nil }
            let id = entityIDs[index]
            index += 1
            return (repeat (each T).makeReadOnlyResolved(access: each accessors, entityID: id))
        }
    }
}

public struct LazyWritableQuerySequence<each T: ComponentResolving>: Sequence {
    @usableFromInline
    internal let entityIDs: [Entity.ID]

    @usableFromInline
    internal let accessors: (repeat TypedAccess<each T>)

    @inlinable @inline(__always)
    init(entityIDs: [Entity.ID], accessors: repeat TypedAccess<each T>) {
        self.entityIDs = entityIDs
        self.accessors = (repeat each accessors)
    }

    @inlinable @inline(__always)
    public func makeIterator() -> AnyIterator<(repeat (each T).ResolvedType)> {
        var index = 0
        return AnyIterator {
            guard index < entityIDs.count else { return nil }
            let id = entityIDs[index]
            index += 1
            return (repeat (each T).makeResolved(access: each accessors, entityID: id))
        }
    }
}
