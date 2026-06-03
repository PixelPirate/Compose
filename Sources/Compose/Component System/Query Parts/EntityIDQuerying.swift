import Foundation

// MARK: - Internal entity-aware query construction

extension Query {
    /// Returns a query that resolves generation-aware `Entity.ID` values.
    ///
    /// Appends a hidden `WithEntityID` component to the type pack so that
    /// observation storage can key rows by generation-aware entity identity,
    /// even when the user's query does not include `WithEntityID`.
    ///
    /// If the user already included `WithEntityID`, the appended component
    /// produces a duplicate entity ID at the end of the output tuple. The
    /// caller tracks which position belongs to the hidden ID.
    @inlinable @inline(__always)
    public func withEntityID() -> Query<repeat each T, WithEntityID> {
        appending(WithEntityID.self)
    }

    /// Whether the query's output tuple already includes `Entity.ID` through `WithEntityID`
    /// in the user-facing component pack.
    @inlinable @inline(__always)
    public var includesEntityID: Bool { isQueryingForEntityID }

    /// Returns generation-aware entity IDs for every entity matching this
    /// query's membership.
    ///
    /// - Note: This runs a full search of the query and is therefore costly. If you also want to access any data, instead use:
    ///   ```
    ///   let result = query.fetchAll(...)
    ///   let ids = result.entityIDs
    ///   ```
    @inlinable @inline(__always)
    public func matchingEntityIDs(in coordinator: Coordinator) -> [Entity.ID] {
        let entityAwareQ = appending(WithEntityID.self)
        let seq = entityAwareQ.fetchAll(coordinator)
        return seq.entityIDs
    }
}
