import Testing
import Components
import Foundation

extension Tag {
  @Tag static var performance: Self
}

@Suite(.tags(.performance)) struct PerformanceTests {
    @Test func testPerformance() throws {
        let query = Query {
            Write<Transform>.self
            Gravity.self
        }
        let clock = ContinuousClock()

        let coordinator = Coordinator()

        let setup = clock.measure {
            for _ in 0...500_000 {
                coordinator.spawn(
                     Gravity(force: Vector3(x: 1, y: 1, z: 1))
                )
            }
            for _ in 0...500_000 {
                coordinator.spawn(
                    Transform(position: .zero, rotation: .zero, scale: .zero),
                    Gravity(force: Vector3(x: 1, y: 1, z: 1))
                )
            }
            for _ in 0...500_000 {
                coordinator.spawn(
                    Transform(position: .zero, rotation: .zero, scale: .zero)
                )
            }
            for _ in 0...500_000 {
                coordinator.spawn(
                    Transform(position: .zero, rotation: .zero, scale: .zero),
                    Gravity(force: Vector3(x: 1, y: 1, z: 1))
                )
            }
        }
        print("Setup:", setup)

        let duration1 = clock.measure {
            query(coordinator) { transform, gravity in
                transform.position.x += gravity.force.x
            }
        }
        let duration2 = clock.measure {
            query(coordinator) { transform, gravity in
                transform.position.x += gravity.force.x
            }
        }
        let duration3 = clock.measure {
            query(coordinator) { transform, gravity in
                transform.position.x += gravity.force.x
            }
        }
    //~0.012 seconds (Iteration)
    //~0.014 seconds (Signature)
        print(duration1, duration2, duration3)
    }

    @Test func testPerformancePreloaded() throws {
        let query = Query {
            Write<Transform>.self
            Gravity.self
        }
        let clock = ContinuousClock()

        let coordinator = Coordinator()

        let setup = clock.measure {
            for _ in 0..<2_000_000 {
                switch Int.random(in: 0...2) {
                case 0:
                    coordinator.spawn(
                        Gravity(force: Vector3(x: 1, y: 1, z: 1))
                    )
                case 1:
                    coordinator.spawn(
                        Transform(position: .zero, rotation: .zero, scale: .zero),
                        Gravity(force: Vector3(x: 1, y: 1, z: 1))
                    )
                case 2:
                    coordinator.spawn(
                        Transform(position: .zero, rotation: .zero, scale: .zero)
                    )
                default:
                    break
                }
            }
        }

        let duration1 = clock.measure {
            query(preloaded: coordinator) { transform, gravity in
                transform.position.x += gravity.force.x
            }
        }
        let duration2 = clock.measure {
            query(preloaded: coordinator) { transform, gravity in
                transform.position.x += gravity.force.x
            }
        }
        let duration3 = clock.measure {
            query(preloaded: coordinator) { transform, gravity in
                transform.position.x += gravity.force.x
            }
        }

        let duration3_1 = clock.measure {
            query(coordinator) { transform, gravity in
                transform.position.x += gravity.force.x
            }
        }
        let duration3_2 = clock.measure {
            query(coordinator) { transform, gravity in
                transform.position.x += gravity.force.x
            }
        }
        let duration3_3 = clock.measure {
            query(coordinator) { transform, gravity in
                transform.position.x += gravity.force.x
            }
        }

        let groupDuration = clock.measure {
            coordinator.addGroup {
                Write<Transform>.self
                Gravity.self
            }
        }

        let duration2_1 = clock.measure {
            query(preloaded: coordinator) { transform, gravity in
                transform.position.x += gravity.force.x
            }
        }
        let duration2_2 = clock.measure {
            query(preloaded: coordinator) { transform, gravity in
                transform.position.x += gravity.force.x
            }
        }
        let duration2_3 = clock.measure {
            query(preloaded: coordinator) { transform, gravity in
                transform.position.x += gravity.force.x
            }
        }

        let duration5_1 = clock.measure {
            query.performGroupDense(coordinator) { transform, gravity in
                transform.position.x += gravity.force.x
            }
        }
        let duration5_2 = clock.measure {
            query.performGroupDense(coordinator) { transform, gravity in
                transform.position.x += gravity.force.x
            }
        }
        let duration5_3 = clock.measure {
            query.performGroupDense(coordinator) { transform, gravity in
                transform.position.x += gravity.force.x
            }
        }

        let duration4_1 = clock.measure {
            query(coordinator) { transform, gravity in
                transform.position.x += gravity.force.x
            }
        }
        let duration4_2 = clock.measure {
            query(coordinator) { transform, gravity in
                transform.position.x += gravity.force.x
            }
        }
        let duration4_3 = clock.measure {
            query(coordinator) { transform, gravity in
                transform.position.x += gravity.force.x
            }
        }

        let setup2 = clock.measure {
            for _ in 0..<2_000_000 {
                switch Int.random(in: 0...2) {
                case 0:
                    coordinator.spawn(
                        Gravity(force: Vector3(x: 1, y: 1, z: 1))
                    )
                case 1:
                    coordinator.spawn(
                        Transform(position: .zero, rotation: .zero, scale: .zero),
                        Gravity(force: Vector3(x: 1, y: 1, z: 1))
                    )
                case 2:
                    coordinator.spawn(
                        Transform(position: .zero, rotation: .zero, scale: .zero)
                    )
                default:
                    break
                }
            }
        }
        print("Setup:", setup)
        print("Post-Group Setup:", setup2)

        //~0.012, 0.007, 0.007 seconds
        print("Pre-Group Perform:", duration3_1, duration3_2, duration3_3)
        print("Pre-Group:", duration1, duration2, duration3)
        print("Group-Build:", groupDuration)
        print("Post-Group:", duration2_1, duration2_2, duration2_3)
        print("Post-Group Specialised:", duration5_1, duration5_2, duration5_3)
        print("Post-Group Perform:", duration4_1, duration4_2, duration4_3)
    }

    @Test func testPerformanceSimple() throws {
        let query = Query {
            Write<Transform>.self
            Gravity.self
        }
        let clock = ContinuousClock()

        let coordinator = Coordinator()

        let setup = clock.measure {
            for _ in 0...1_000_000 {
                coordinator.spawn(
                    Transform(position: .zero, rotation: .zero, scale: .zero),
                    Gravity(force: Vector3(x: 0, y: 0, z: 0))
                )
            }
        }
        print("Setup:", setup)

        let duration = clock.measure {
            query(coordinator) { transform, gravity in
                transform.position.x += gravity.force.x
            }
        }
        // Bevy seems to need 6.7ms for this (Archetypes), 12.5ms with sparse sets
        //~0.011 seconds (Iteration)
        //~0.014 seconds (Signature)
        print(duration)
    }

    @Test func testPerformanceParallel() {
        let coordinator = Coordinator()
        for _ in 0...200 {
            coordinator.spawn(
                Transform(position: .zero, rotation: .zero, scale: .zero),
                Gravity(force: Vector3(x: 10, y: 10, z: 10))
            )
        }
        class BaseTestSystem: System {
            class var id: SystemID { SystemID(name: "TestSystem") }

            var metadata: SystemMetadata {
                Self.metadata(from: [queryA.metadata, queryB.metadata])
            }

            let queryA = Query {
                Transform.self
            }

            let queryB = Query {
                Gravity.self
            }

            func run(context: QueryContext, commands: inout Commands) {
                if Bool.random() {
                    queryA(context) { transform in
                        var value = context[resource: Float.self]
                        value += sin(abs(pow(Float(expensiveOperation()), 2)))
                        context[resource: Float.self] = value
                    }
                } else {
                    queryB(context) { gravity in
                        var value = context[resource: Float.self]
                        value += sin(abs(pow(Float(expensiveOperation()), 2)))
                        context[resource: Float.self] = value
                    }
                }
            }

            func expensiveOperation(size: Int = 50) -> Int {
                var a = [[Int]]()
                var b = [[Int]]()

                // Initialise matrices
                for i in 0..<size {
                    a.append((0..<size).map { i + $0 })
                    b.append((0..<size).map { i * $0 })
                }

                // Multiply matrices
                var result = Array(repeating: Array(repeating: 0, count: size), count: size)
                for i in 0..<size {
                    for j in 0..<size {
                        var sum = 0
                        for k in 0..<size {
                            sum += a[i][k] * b[k][j]
                        }
                        result[i][j] = sum
                    }
                }

                // Return something to prevent compiler optimisation
                return result[0][0]
            }
        }
        final class System1: BaseTestSystem {
            override static var id: SystemID {
                SystemID(name: "1")
            }
        }
        final class System2: BaseTestSystem {
            override static var id: SystemID {
                SystemID(name: "2")
            }
        }
        final class System3: BaseTestSystem {
            override static var id: SystemID {
                SystemID(name: "3")
            }
        }
        final class System4: BaseTestSystem {
            override static var id: SystemID {
                SystemID(name: "4")
            }
        }
        final class System5: BaseTestSystem {
            override static var id: SystemID {
                SystemID(name: "5")
            }
        }
        final class System6: BaseTestSystem {
            override static var id: SystemID {
                SystemID(name: "6")
            }
        }
        final class System7: BaseTestSystem {
            override static var id: SystemID {
                SystemID(name: "7")
            }
        }
        final class System8: BaseTestSystem {
            override static var id: SystemID {
                SystemID(name: "8")
            }
        }
        final class System9: BaseTestSystem {
            override static var id: SystemID {
                SystemID(name: "9")
            }
        }
        final class System10: BaseTestSystem {
            override static var id: SystemID {
                SystemID(name: "10")
            }
        }
        coordinator[resource: Float.self] = 0
        coordinator.addSystem(.update, system: System1())
        coordinator.addSystem(.update, system: System2())
        coordinator.addSystem(.update, system: System3())
        coordinator.addSystem(.update, system: System4())
        coordinator.addSystem(.update, system: System5())
        coordinator.addSystem(.update, system: System6())
        coordinator.addSystem(.update, system: System7())
        coordinator.addSystem(.update, system: System8())
        coordinator.addSystem(.update, system: System9())
        coordinator.addSystem(.update, system: System10())
        coordinator.update(.update) {
            $0.executor = MultiThreadedExecutor()
        }
        let clock = ContinuousClock()
        let multiDuration1 = clock.measure {
            coordinator.runSchedule(.update)
        }
        let multiDuration2 = clock.measure {
            coordinator.runSchedule(.update)
        }
        let multiDuration3 = clock.measure {
            coordinator.runSchedule(.update)
        }
        coordinator.update(.update) {
            $0.executor = SingleThreadedExecutor()
        }
        let singleDuration1 = clock.measure {
            coordinator.runSchedule(.update)
        }
        let singleDuration2 = clock.measure {
            coordinator.runSchedule(.update)
        }
        let singleDuration3 = clock.measure {
            coordinator.runSchedule(.update)
        }
        print("Single threaded:", singleDuration1, singleDuration2, singleDuration3)
        print("Multi threaded:", multiDuration1, multiDuration2, multiDuration3)
    }
    
    @Test func testPerformanceManyComponents() {
        struct MockComponent: Component {
            nonisolated(unsafe) static var componentTag: ComponentTag = ComponentTag(rawValue: 0)

            var numberWang: Int = 12
        }

        struct Component_1: Component {
            nonisolated(unsafe) static var componentTag: ComponentTag = ComponentTag(rawValue: 1)

            var numberWang: Int = 12
        }
        struct Component_2: Component {
            nonisolated(unsafe) static var componentTag: ComponentTag = ComponentTag(rawValue: 2)

            var numberWang: Int = 12
        }
        struct Component_3: Component {
            nonisolated(unsafe) static var componentTag: ComponentTag = ComponentTag(rawValue: 3)

            var numberWang: Int = 12
        }
        struct Component_4: Component {
            nonisolated(unsafe) static var componentTag: ComponentTag = ComponentTag(rawValue: 4)

            var numberWang: Int = 12
        }
        struct Component_5: Component {
            nonisolated(unsafe) static var componentTag: ComponentTag = ComponentTag(rawValue: 5)

            var numberWang: Int = 12
        }

        let coordinator = Coordinator()
        let mockComponent = MockComponent()

        for componentNumber in 10..<150 {
            MockComponent.componentTag = ComponentTag(rawValue: componentNumber)
            for _ in 0..<2_000 {
                coordinator.spawn(mockComponent)
            }
            for _ in 0..<2_000 {
                let entity = coordinator.spawn()
                for otherComponentNumber in 10..<componentNumber {
                    MockComponent.componentTag = ComponentTag(rawValue: otherComponentNumber)
                    coordinator.add(mockComponent, to: entity)
                }
            }
        }
        for _ in 0..<10_000 {
            coordinator.spawn(Component_1())
            coordinator.spawn(Component_2())
            coordinator.spawn(Component_3())
            coordinator.spawn(Component_4())
            coordinator.spawn(Component_5())
            coordinator.spawn(Component_1(), Component_2())
            coordinator.spawn(Component_1(), Component_2(), Component_3())
            coordinator.spawn(Component_1(), Component_2(), Component_3(), Component_4())
            coordinator.spawn(Component_1(), Component_2(), Component_3(), Component_4(), Component_5())
        }

        let query = Query {
            Write<Component_1>.self
            Component_2.self
            Component_3.self
            With<Component_4>.self
            Without<Component_5>.self
        }

        let clock = ContinuousClock()
        let duration = clock.measure {
            for _ in 0..<10_000 {
                query(coordinator) { com1, com2, com3 in
                    com1.numberWang = com2.numberWang * com3.numberWang * com2.numberWang
                }
            }
        }

        // Big version: 2.43s (appDev)

        //~0.00026 seconds (Iteration)
        //~0.00030 seconds (Signature)
        print(duration)
    }

    @Test func testPerformanceRepeat() {
        let clock = ContinuousClock()
        let coordinator = Coordinator()
        for _ in 0..<10_000 {
            coordinator.spawn(
                Transform(position: .zero, rotation: .zero, scale: .zero),
                Gravity(force: .zero)
            )
        }

        let query = Query { Write<Transform>.self; Gravity.self }

        let setup1 = clock.measure {
            for _ in 0..<1000 {
                query(coordinator) { transform, gravity in
                    transform.position.x += gravity.force.x
                }
            }
        }
        print("first run:", setup1)

        let setup2 = clock.measure {
            for _ in 0..<1000 {
                query(coordinator) { transform, gravity in
                    transform.position.x += gravity.force.x
                }
            }
        }
        print("second run (cached):", setup2)

        // (Iteration)
        //first run: 0.112772916 seconds
        //second run (cached): 0.113031667 seconds
        // (Signature)
        //first run: 0.113668375 seconds
        //second run (cached): 0.114894083 seconds
    }

    @Test func iterPerformance() throws {
        let coordinator = Coordinator()

        for _ in 0..<1_000_000 {
            coordinator.spawn(
                Transform(position: .zero, rotation: .zero, scale: .zero),
                Gravity(force: Vector3(x: 1, y: 1, z: 1))
            )
        }

        let query = Query {
            Write<Transform>.self
            Gravity.self
        }

        let clock = ContinuousClock()

        let iterDuration = clock.measure {
            let transforms = query.unsafeFetchAllWritable(coordinator)

            for (transform, gravity) in transforms {
                transform.position.x += gravity.force.x
            }
        }

        let performDuration = clock.measure {
            query(coordinator) { transform, gravity in
                transform.position.x += gravity.force.x
            }
        }

        print("Iter:", iterDuration, "Perform:", performDuration)
    }


    @Test func ecsBenchmark() {
        let clock = ContinuousClock()

        func seconds(_ d: Duration) -> Double {
            let c = d.components
            return Double(c.seconds) + Double(c.attoseconds) / 1e18
        }

        func measure(_ name: String, _ block: () -> Void) -> Duration {
            let d = clock.measure(block)
            print(name + ":", d)
            return d
        }

        func measureCount(_ name: String, count: Int, _ block: () -> Void) -> Duration {
            let d = clock.measure(block)
            let s = seconds(d)
            if s > 0 {
                let rate = Double(count) / s
                print("\(name): \(d) (\(Int(rate)) ops/s)")
            } else {
                print("\(name): \(d) (inf ops/s)")
            }
            return d
        }

        struct Health: Component, Equatable, Sendable { static let componentTag = ComponentTag.makeTag(); var hp: Int }
        struct Mana: Component, Equatable, Sendable { static let componentTag = ComponentTag.makeTag(); var mp: Int }
        struct AI: Component, Sendable { static let componentTag = ComponentTag.makeTag(); var state: Int }
        struct Renderable: Component, Sendable { static let componentTag = ComponentTag.makeTag(); var meshID: Int }
        struct TagA: Component, Sendable { static let componentTag = ComponentTag.makeTag(); init() {} }
        struct TagB: Component, Sendable { static let componentTag = ComponentTag.makeTag(); init() {} }

        let N = 300_000
        let coordinator = Coordinator()

        // Spawn distributions: empty, 1C, 2C, 3C, 4C, mixed
        _ = measureCount("Spawn-Mixed", count: N) {
            for i in 0..<N {
                switch i & 7 {
                case 0:
                    _ = coordinator.spawn()
                case 1:
                    _ = coordinator.spawn(Transform(position: .zero, rotation: .zero, scale: .zero))
                case 2:
                    _ = coordinator.spawn(Gravity(force: Vector3(x: 1, y: 2, z: 3)))
                case 3:
                    _ = coordinator.spawn(Transform(position: .zero, rotation: .zero, scale: .zero), Gravity(force: Vector3(x: 1, y: 2, z: 3)))
                case 4:
                    _ = coordinator.spawn(Health(hp: 100))
                case 5:
                    _ = coordinator.spawn(Mana(mp: 50), Renderable(meshID: 42))
                case 6:
                    _ = coordinator.spawn(AI(state: 0), TagA())
                default:
                    _ = coordinator.spawn(Transform(position: .zero, rotation: .zero, scale: .zero), Gravity(force: .zero), Health(hp: 1), Mana(mp: 1))
                }
            }
        }

        // Baseline iteration: Write<Transform> + Gravity
        let qMove = Query { Write<Transform>.self; Gravity.self }
        _ = measure("Query-Perform Move") {
            qMove(coordinator) { t, g in
                t.position.x += g.force.x
            }
        }

        // Signature-based iteration path
        _ = measure("Query-PerformWithSignature Move") {
            qMove.performWithSignature(coordinator) { t, g in
                t.position.x += g.force.x
            }
        }

        // FetchAll vs IterAll vs Perform
        _ = measure("Query-FetchAll Move") {
            let all = Array(qMove.fetchAll(coordinator))
            #expect(!all.isEmpty)
        }

        _ = measure("Query-IterAll Move") {
            let seq = qMove.unsafeFetchAllWritable(coordinator)
            for (t, g) in seq { t.position.x += g.force.x }
        }

        // With/Without filters
        let qFiltered = Query { Write<Transform>.self; With<Gravity>.self; Without<RigidBody>.self }
        _ = measure("Query-Filters With/Without") {
            qFiltered(coordinator) { t in t.position.y += 1 }
        }

        // Include Entity ID
        let qWithID = Query { WithEntityID.self; Transform.self }
        _ = measure("Query-WithEntityID") {
            qWithID(coordinator) { (_: Entity.ID, _: Transform) in }
        }

        // Prepare churn selection outside measurement and add sanity counts
        var rng = SystemRandomNumberGenerator()
        let idsQuery = Query { WithEntityID.self }
        let allIDs = Array(idsQuery.fetchAll(coordinator)).map { $0 }
        #expect(!allIDs.isEmpty)

        // Precompute a 1/3 selection mask
        var selected: [Bool] = .init(repeating: false, count: allIDs.count)
        for i in 0..<allIDs.count { selected[i] = (Int.random(in: 0..<3, using: &rng) == 0) }

        // Count entities with Health before/after
        func countWithHealth() -> Int {
            Array(Query { WithEntityID.self; With<Health>.self }.fetchAll(coordinator)).count
        }
        let healthBefore = countWithHealth()

        _ = measure("Churn-AddRemove Health") {
            for (i, id) in allIDs.enumerated() where selected[i] {
                coordinator.add(Health(hp: 10), to: id)
            }
            for (i, id) in allIDs.enumerated() where selected[i] {
                coordinator.remove(Health.self, from: id)
            }
        }
        let healthAfter = countWithHealth()
        print("Churn sanity: before=\(healthBefore) after=\(healthAfter) delta=\(healthAfter - healthBefore)")

        // Destroy and respawn half the world (deterministic subset)
        let toDestroy = allIDs.enumerated().compactMap { (i, id) in (i & 1) == 0 ? id : nil }
        _ = measureCount("Destroy-Half", count: toDestroy.count) {
            for id in toDestroy { coordinator.destroy(id) }
        }

        // Respawn exactly the same count, mixed components
        _ = measureCount("Respawn-Half", count: toDestroy.count) {
            for i in 0..<toDestroy.count {
                switch i & 3 {
                case 0:
                    _ = coordinator.spawn(Transform(position: .zero, rotation: .zero, scale: .zero))
                case 1:
                    _ = coordinator.spawn(Gravity(force: .zero))
                case 2:
                    _ = coordinator.spawn(Transform(position: .zero, rotation: .zero, scale: .zero), Gravity(force: .zero))
                default:
                    _ = coordinator.spawn(Health(hp: 5), Mana(mp: 5))
                }
            }
        }

        // Parallel iteration with heavier per-entity work to amortize overhead
        let workIters = 32
        _ = measure("Query-Parallel Move (heavier)") {
            qMove(parallel: coordinator) { t, g in
                var ax = t.position.x
                let gx = g.force.x
                var i = 0
                while i < workIters {
                    ax = (ax + gx) * 1.0001 - gx * 0.9999
                    i += 1
                }
                t.position.x = ax
            }
        }

        // Combination queries (pairwise interactions on a subset)
        let pairQuery = Query { Write<Transform>.self; With<TagA>.self; Without<TagB>.self }
        _ = measure("Query-Combinations Pairwise") {
            pairQuery(combinations: coordinator) { a, b in
                let (ta) = a.values
                let (tb) = b.values
                ta.position.x += 0.001
                tb.position.x -= 0.001
            }
        }

        // Cache effect: run the same query twice back-to-back to observe plan reuse
        _ = measure("Cache-First Run") {
            qMove(coordinator) { t, g in t.position.x += g.force.x }
        }
        _ = measure("Cache-Second Run") {
            qMove(coordinator) { t, g in t.position.x += g.force.x }
        }

        // Mixed complex query resembling a gameplay frame
        let complexQuery = Query {
            Write<Transform>.self
            Gravity.self
            With<Health>.self
            Without<TagB>.self
        }
        _ = measure("Frame-Mix Update") {
            complexQuery(coordinator) { t, g in
                t.position.x += g.force.x
                t.position.y += g.force.y
                t.position.z += g.force.z
            }
        }
    }

    @Test func ecsCacheMicroBenchmark() {
        let clock = ContinuousClock()
        func seconds(_ d: Duration) -> Double {
            let c = d.components
            return Double(c.seconds) + Double(c.attoseconds) / 1e18
        }
        func measure(_ name: String, _ block: () -> Void) -> Duration {
            let d = clock.measure(block)
            print(name + ":", d)
            return d
        }

        let coordinator = Coordinator()
        let N = 300_000
        for _ in 0..<N {
            _ = coordinator.spawn(
                Transform(position: .zero, rotation: .zero, scale: .zero),
                Gravity(force: .zero)
            )
        }
        let qMove = Query { Write<Transform>.self; Gravity.self }
        let first = measure("CacheMicro-First") {
            qMove(coordinator) { t, g in t.position.x += g.force.x }
        }
        let second = measure("CacheMicro-Second") {
            qMove(coordinator) { t, g in t.position.x += g.force.x }
        }
        let s1 = seconds(first), s2 = seconds(second)
        if s2 > 0 { print("CacheMicro ratio (second/first):", s2 / s1) }
    }
}

public struct Downward: Component, Sendable {
    public static var componentTag: ComponentTag { Transform.componentTag }

    let isDownward: Bool

    public init(isDownward: Bool) {
        print("is", isDownward)
        self.isDownward = isDownward
    }

    @inlinable @inline(__always)
    public static func makeResolved(access: TypedAccess<Transform>, entityID: Entity.ID) -> Downward {
        print("called")
        return Downward(isDownward: access.access(entityID).value.position.y < 0)
    }

    @inlinable @inline(__always)
    public static func makeReadOnlyResolved(access: TypedAccess<Transform>, entityID: Entity.ID) -> Downward {
        print("called readonly", entityID, access.access(entityID).value.position.y)
        return Downward(isDownward: access.access(entityID).value.position.y < 0)
    }
}

public struct Vector3: Hashable, Sendable {
    public var x: Float
    public var y: Float
    public var z: Float

    public static let zero = Vector3(x: 0, y: 0, z: 0)

    public init(x: Float, y: Float, z: Float) {
        self.x = x
        self.y = y
        self.z = z
    }
}

public struct Gravity: Component, Sendable {
    public static let componentTag = ComponentTag.makeTag()

    public var force: Vector3

    public init(force: Vector3) {
        self.force = force
    }
}

public struct RigidBody: Component, Equatable {
    public static let componentTag = ComponentTag.makeTag()

    public var velocity: Vector3
    public var acceleration: Vector3

    public init(velocity: Vector3, acceleration: Vector3) {
        self.velocity = velocity
        self.acceleration = acceleration
    }
}

public struct Transform: Equatable, Component, Sendable {
    public static let componentTag = ComponentTag.makeTag()

    public var position: Vector3
    public var rotation: Vector3
    public var scale: Vector3

    public init(position: Vector3, rotation: Vector3, scale: Vector3) {
        self.position = position
        self.rotation = rotation
        self.scale = scale
    }
}

public struct Person: Component {
    public static let componentTag = ComponentTag.makeTag()

    public init() {
    }
}

