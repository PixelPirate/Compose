import Foundation

// MARK: - ObservationDiffingQuery

/// Builds a single query that detects **any** change to tracked components
/// since the querying system last ran.
///
/// ## Design
///
/// The diffing query uses `Or<Added<C>, Changed<C>, Removed<C>>` filters so
/// that a single query execution covers all three change kinds. This avoids
/// the correctness pitfalls of running separate `Added`, `Changed`, and
/// `Removed` queries whose disjoint result sets may not reconcile cleanly for
/// entities that undergo multiple changes in a single tick.
///
/// The query returns only `Entity.ID` values — it has no component outputs.
/// The observation system separately resolves current membership and
/// component values for each affected entity. This deferred resolution is
/// acceptable because only **changed** entities go through it; unchanged
/// entities incur zero overhead.
///
/// ## How the observation system uses the result
///
/// For each entity ID returned by the diffing query, the system must
/// determine the correct action:
///
/// 1. **Check current membership** against the original query's rules:
///    - All required components present? All backstage components present?
///    - No excluded components present?
///
/// 2. **If membership passes** → upsert in storage (resolve and store
///    the full output element).
///
/// 3. **If membership fails** → remove from storage (the entity lost a
///    required component or gained an excluded one).
///
/// 4. **Optional output components** that transition to `nil` do NOT
///    cause removal — they only update the stored element to its new
///    `nil` value. The system uses the `Removed<C>` signal to detect
///    this transition.
///
/// 5. **Same-tick conflicts** (e.g. entity removed and re-added within
///    one tick) are reconciled against final world membership: the
///    system reads the coordinator's current state, not intermediate
///    deltas.
///
/// ## Edge cases
///
/// - **`With<C>` where C appears both as output and filter**: no
///   duplicate change tracking. The component is tracked once via its
///   output role; the filter role is satisfied by the membership check
///   in step 2.
/// - **`Without<C>`**: the excluded component is tracked via
///   `Or<Added<C>, Removed<C>>` — `Added` signals the entity gained
///   the excluded component (remove from storage), `Removed` signals
///   it lost the excluded component (candidate for upsert).
/// - **Destroyed entities**: are NOT tracked by change filters (per
///   `Removed<C>` semantics). Destroyed-entity removal is handled by
///   the observation system checking `coordinator.isAlive(_:)`
///   separately.
@usableFromInline
struct ObservationDiffingQuery {
    /// The runnable query: returns only entity IDs for changed entities.
    @usableFromInline
    let query: Query<WithEntityID>

    /// Components the original query **requires** (output + backstage).
    /// An entity must currently have all of these AND none of `excludedTags`
    /// to be considered a member.
    @usableFromInline
    let requiredTags: Set<ComponentTag>

    /// Components the original query **excludes**.
    @usableFromInline
    let excludedTags: Set<ComponentTag>

    /// Tags that appear as output components in the original query.
    /// The observation system resolves values for these when upserting.
    @usableFromInline
    let outputTags: Set<ComponentTag>

    /// Tags that appear as optional output components in the original query.
    /// These may legitimately be `nil` without affecting membership.
    @usableFromInline
    let optionalTags: Set<ComponentTag>

    @usableFromInline
    init(
        query: Query<WithEntityID>,
        requiredTags: Set<ComponentTag>,
        excludedTags: Set<ComponentTag>,
        outputTags: Set<ComponentTag>,
        optionalTags: Set<ComponentTag>
    ) {
        self.query = query
        self.requiredTags = requiredTags
        self.excludedTags = excludedTags
        self.outputTags = outputTags
        self.optionalTags = optionalTags
    }
}

extension Query where repeat each T: ComponentResolving {
    /// Builds a single diffing query and metadata for observation.
    ///
    /// The receiver must be a user-facing query with **no** change filters.
    @usableFromInline
    func buildObservationDiffingQuery() -> ObservationDiffingQuery {
        var outputTags = Set<ComponentTag>()
        var optionalTags = Set<ComponentTag>()
        var changeTags = Set<ComponentTag>()

        // Enumerate output components (variadic type pack)
        for compType in repeat (each T).self {
            guard compType.QueriedComponent.self != Never.self else { continue }
            let tag = compType.componentTag
            outputTags.insert(tag)
            changeTags.insert(tag)
            if compType is any OptionalQueriedComponent.Type {
                optionalTags.insert(tag)
            }
        }

        // Track backstage components separately (not in output)
        for tag in backstageComponents where !outputTags.contains(tag) {
            changeTags.insert(tag)
        }

        // Track excluded components separately
        for tag in excludedComponents {
            changeTags.insert(tag)
        }

        // Build the diffing query: entirely unconstrained (no backstage,
        // no excluded), uses Or{Added,Changed,Removed} for each tracked tag.
        //
        // For output components:    Or<Added, Changed, Removed>
        // For backstage components: Or<Added, Removed>      (changed irrelevant)
        // For excluded components:  Or<Added, Removed>
        var orFilters: [ChangeFilter] = []
        for tag in changeTags {
            var conditions: Set<ChangeFilter.ComponentCondition> = []
            if outputTags.contains(tag) {
                conditions.insert(ChangeFilter.ComponentCondition(tag: tag, condition: .added))
                conditions.insert(ChangeFilter.ComponentCondition(tag: tag, condition: .changed))
                conditions.insert(ChangeFilter.ComponentCondition(tag: tag, condition: .removed))
            } else {
                // backstage or excluded: only added/removed matter
                conditions.insert(ChangeFilter.ComponentCondition(tag: tag, condition: .added))
                conditions.insert(ChangeFilter.ComponentCondition(tag: tag, condition: .removed))
            }
            orFilters.append(ChangeFilter(.or(conditions)))
        }

        let diffQuery = Query<WithEntityID>(
            backstageComponents: [],
            excludedComponents: [],
            changeFilters: Set(orFilters),
            isQueryingForEntityID: true
        )

        let requiredTags = outputTags.subtracting(optionalTags).union(backstageComponents)

        return ObservationDiffingQuery(
            query: diffQuery,
            requiredTags: requiredTags,
            excludedTags: excludedComponents,
            outputTags: outputTags,
            optionalTags: optionalTags
        )
    }
}