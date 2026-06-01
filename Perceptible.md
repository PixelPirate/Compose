I added the pointfreeco/swift-perception package. It reimplements the Apple "@Observable" macro.

We need a new feature, using the query change filters "Added<…>, Changed<…>, Removed<…>", we need to implement a wrapper for `Query` which is perceptible.

The idea is that we can use Compose inside SwiftUI using swift-perception. E.g.:
```swift
import Perceptible
struct MyView: View {
    let coordinator: Coordinator
    @State var entities = PerceptibleQuery { Transform.self; WithEntityID.self }
    var body: some View {
        WithPerceptionTracking {
            VStack {
                ForEach(entities.observe(coordinator), id: \.1) { entity in // `entity` is `(Transform, Entity.ID)`.
                    HStack {
                        Text(verbatim: String(entity.1)) // Entity.ID
                        Text(verbatim: String(entity.0.position.x))
                    }
                }
            }
        }
    }
}
```

So the first call to `.observe` needs to start some sort of observation task inside `PerceptibleQuery`. Every time it detects a change, it needs to emit that through `swift-perception`. This would then cause `WithPerceptionTracking` to rerender which causes a new call to `.observe` which then returns the updated array of results.
For best performance it would be best if `.observe` just returns cached results from inside `PerceptibleQuery`, so that when `PerceptibleQuery` internally fetches data and detects an update, the next call to `.observe` can just return that data without any new calculation.

`PerceptibleQuery` will internally have a `Query` type build from the initialiser `QueryBuilder`. There is already a helper on Query: `Query.tracking()` which adds `Added<…>` and `Changed<…>` to all required components of the given query. I would expect that `PerceptibleQuery` applied that helper on the query in it's initialiser. (`PerceptibleQuery.init(…) { let query: ...; self.query = query.tracking() }`).
