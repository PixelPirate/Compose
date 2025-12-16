# Compose
A Swift ECS

## SwiftUI bridge helpers
When bridging queries into SwiftUI, you can simplify change tracking by calling `.tracking()` on a `Query`. This automatically adds `Added` and `Changed` filters for every returned component (excluding backstage and excluded components), so the query only reports entities that were created or modified since the last run.

For situations where you need to know why a query returned no data, use `fetchAllWithState(_:)` or `fetchOneWithState(_:)`. These return a `QueryFetchResult` that distinguishes between:
* `.noEntities` – nothing in the world matches the query components (for example, the last entity was removed).
* `.unchanged` – matching entities exist, but none satisfied the added/changed filters during this tick.
* `.results` – the queried entities for the current tick.

These helpers let a SwiftUI property wrapper update only when meaningful changes occur while still clearing state when entities disappear.
