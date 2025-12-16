# Compose
A Swift ECS

## SwiftUI integration helpers

`Query.tracking()` can be used to automatically append `Added`/`Updated` change filters for every queried component (excluding filters such as `With`, `Without`, or `WithEntityID`). When mirroring ECS data into SwiftUI, call `fetchOneWithStatus` or `fetchAllWithStatus` to get both the query results and a `hasMatches` flag that tells you whether the world currently contains entities matching the query (ignoring change filters). This lets SwiftUI drive updates only when data actually changes or disappears.
