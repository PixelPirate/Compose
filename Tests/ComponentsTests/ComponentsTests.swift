import Testing
@testable import Components
import Synchronization
import Atomics
import Foundation

final class ConcurrentAccessProbe {
    private let active = ManagedAtomic<Int>(0)
    private let violation = ManagedAtomic<Bool>(false)

    func enter() {
        let newValue = active.wrappingIncrementThenLoad(ordering: .acquiring)
        if newValue > 1 {
            violation.store(true, ordering: .relaxed)
        }
    }

    func leave() {
        active.wrappingDecrement(ordering: .releasing)
    }

    var hadViolation: Bool {
        violation.load(ordering: .relaxed)
    }
}

@Test func testQueryPerform() async throws {
    let query = Query {
        Write<Transform>.self
        Gravity.self
    }

    let coordinator = Coordinator()

    for _ in 0..<500 {
        coordinator.spawn(
             Gravity(force: Vector3(x: 1, y: 1, z: 1))
        )
    }
    for _ in 0..<500 {
        coordinator.spawn(
            Transform(position: .zero, rotation: .zero, scale: .zero),
            Gravity(force: Vector3(x: 1, y: 1, z: 1))
        )
    }
    for _ in 0..<500 {
        coordinator.spawn(
            Transform(position: .zero, rotation: .zero, scale: .zero)
        )
    }
    for _ in 0..<500 {
        coordinator.spawn(
            Transform(position: .zero, rotation: .zero, scale: .zero),
            Gravity(force: Vector3(x: 1, y: 1, z: 1))
        )
    }

    await confirmation(expectedCount: 1_000) { confirm in
        query(coordinator) { transform, gravity in
            transform.position.x += gravity.force.x
            confirm()
        }
    }
}

@Test func fixedLoop() async throws {
    await confirmation(expectedCount: 64) { confirmation in
        struct TestSystem: System {
            var metadata: SystemMetadata {
                TestSystem.metadata(from: [])
            }

            static let id = SystemID(name: "MySystem")

            let confirmation: Confirmation

            func run(context: Components.QueryContext, commands: inout Components.Commands) {
                confirmation()
            }
        }

        let coordinator = Coordinator()
        coordinator.addSystem(.fixedUpdate, system: TestSystem(confirmation: confirmation))

        coordinator[resource: WorldClock.self] = coordinator[resource: WorldClock.self].advancing(by: 1.0)
        coordinator.run()
    }
}

@Test func updateExecutor() async throws {
    let coordinator = Coordinator()
    struct TestSystem: System {
        static let id = SystemID(name: "TestSystem")
        var metadata: SystemMetadata {
            Self.metadata(from: [])
        }

        let confirmation: Confirmation

        func run(context: Components.QueryContext, commands: inout Components.Commands) {
            confirmation()
        }
    }
    struct TestExecutor: Executor {
        let confirmation: Confirmation
        func run(systems: ArraySlice<any Components.System>, coordinator: Components.Coordinator, commands: inout Components.Commands) {
            confirmation()
            for system in systems {
                system.run(context: QueryContext(coordinator: coordinator), commands: &commands)
            }
        }
    }
    await confirmation(expectedCount: 1) { systemConfirmation in
        await confirmation(expectedCount: 1) { executorConfirmation in
            coordinator.addSystem(.update, system: TestSystem(confirmation: systemConfirmation))
            #expect(coordinator.systemManager.schedules[.update]?.executor is MultiThreadedExecutor)
            coordinator.update(.update) { schedule in
                schedule.executor = TestExecutor(confirmation: executorConfirmation)
            }
            coordinator.runSchedule(.update)
        }
    }
}

@Test func systemOrder() throws {
    let coordinator = Coordinator()

    struct TestSystem1: System {
        static let id = SystemID(name: "TestSystem1")
        var metadata: SystemMetadata {
            Self.metadata(from: [])
        }

        let confirmation: () -> Void

        func run(context: Components.QueryContext, commands: inout Components.Commands) {
            confirmation()
        }
    }

    struct TestSystem2: System {
        static let id = SystemID(name: "TestSystem2")
        var metadata: SystemMetadata {
            Self.metadata(from: [])
        }

        let confirmation: () -> Void

        func run(context: Components.QueryContext, commands: inout Components.Commands) {
            confirmation()
        }
    }

    struct TestSystem3: System {
        static let id = SystemID(name: "TestSystem3")
        var metadata: SystemMetadata {
            Self.metadata(from: [], runAfter: [TestSystem2.id])
        }

        let confirmation: () -> Void

        func run(context: Components.QueryContext, commands: inout Components.Commands) {
            confirmation()
        }
    }

    let lock: Mutex<[SystemID]> = Mutex([])

    coordinator.addSystem(.update, system: TestSystem1 { lock.withLock { $0.append(TestSystem1.id) } })
    coordinator.addSystem(.update, system: TestSystem3 { lock.withLock { $0.append(TestSystem3.id) } })
    coordinator.addSystem(.update, system: TestSystem2 { lock.withLock { $0.append(TestSystem2.id) } })

    coordinator.update(.update) { $0.executor = MultiThreadedExecutor() }

    coordinator.runSchedule(.update)

    let result1 = lock.withLock { $0 }

    #expect(result1 == [TestSystem1.id, TestSystem2.id, TestSystem3.id])

    lock.withLock { $0.removeAll() }

    coordinator.update(.update) { $0.executor = SingleThreadedExecutor() }

    coordinator.runSchedule(.update)

    let result2 = lock.withLock { $0 }

    #expect(result2 == [TestSystem1.id, TestSystem2.id, TestSystem3.id])
}

@Test func multiThreadedExecutorAvoidsConcurrentComponentMutations() {
    struct ComponentWriterA: System {
        static let id = SystemID(name: "ComponentWriterA")
        nonisolated(unsafe) static let query = Query { Write<Transform>.self }

        let probe: ConcurrentAccessProbe

        var metadata: SystemMetadata {
            Self.metadata(from: [Self.query.schedulingMetadata])
        }

        func run(context: Components.QueryContext, commands: inout Components.Commands) {
            probe.enter()
            defer { probe.leave() }

            Self.query(context) { (transform: Write<Transform>) in
                transform.position.x += 1
            }

            Thread.sleep(forTimeInterval: 0.01)
        }
    }

    struct ComponentWriterB: System {
        static let id = SystemID(name: "ComponentWriterB")
        nonisolated(unsafe) static let query = ComponentWriterA.query

        let probe: ConcurrentAccessProbe

        var metadata: SystemMetadata {
            Self.metadata(from: [Self.query.schedulingMetadata])
        }

        func run(context: Components.QueryContext, commands: inout Components.Commands) {
            probe.enter()
            defer { probe.leave() }

            Self.query(context) { (transform: Write<Transform>) in
                transform.position.x += 1
            }

            Thread.sleep(forTimeInterval: 0.01)
        }
    }

    let probe = ConcurrentAccessProbe()
    let coordinator = Coordinator()
    let entityCount = max(2, ProcessInfo.processInfo.processorCount) * 2

    for _ in 0..<entityCount {
        coordinator.spawn(
            Transform(position: .zero, rotation: .zero, scale: .zero)
        )
    }

    coordinator.addSystem(.update, system: ComponentWriterA(probe: probe))
    coordinator.addSystem(.update, system: ComponentWriterB(probe: probe))

    coordinator.runSchedule(.update)

    #expect(!probe.hadViolation)

    let transforms = Array(Query { Transform.self }.fetchAll(coordinator))
    #expect(transforms.count == entityCount)
    #expect(transforms.allSatisfy { $0.position.x == Float(2) })
}

@Test func multiThreadedExecutorAvoidsConcurrentResourceMutations() {
    struct SharedCounterResource: Sendable {
        var value: Int
    }

    struct ResourceWriterA: System {
        static let id = SystemID(name: "ResourceWriterA")

        let probe: ConcurrentAccessProbe

        var metadata: SystemMetadata {
            SystemMetadata(
                id: Self.id,
                readSignature: ComponentSignature(),
                writeSignature: ComponentSignature(),
                excludedSignature: ComponentSignature(),
                runAfter: [],
                resourceAccess: [(ResourceKey(SharedCounterResource.self), .write)],
                eventAccess: []
            )
        }

        func run(context: Components.QueryContext, commands: inout Components.Commands) {
            probe.enter()
            defer { probe.leave() }

            var counter = context.coordinator[resource: SharedCounterResource.self]
            counter.value += 1
            context.coordinator[resource: SharedCounterResource.self] = counter

            Thread.sleep(forTimeInterval: 0.01)
        }
    }

    struct ResourceWriterB: System {
        static let id = SystemID(name: "ResourceWriterB")

        let probe: ConcurrentAccessProbe

        var metadata: SystemMetadata {
            SystemMetadata(
                id: Self.id,
                readSignature: ComponentSignature(),
                writeSignature: ComponentSignature(),
                excludedSignature: ComponentSignature(),
                runAfter: [],
                resourceAccess: [(ResourceKey(SharedCounterResource.self), .write)],
                eventAccess: []
            )
        }

        func run(context: Components.QueryContext, commands: inout Components.Commands) {
            probe.enter()
            defer { probe.leave() }

            var counter = context.coordinator[resource: SharedCounterResource.self]
            counter.value += 1
            context.coordinator[resource: SharedCounterResource.self] = counter

            Thread.sleep(forTimeInterval: 0.01)
        }
    }

    let probe = ConcurrentAccessProbe()
    let coordinator = Coordinator()
    coordinator.addRessource(SharedCounterResource(value: 0))

    coordinator.addSystem(.update, system: ResourceWriterA(probe: probe))
    coordinator.addSystem(.update, system: ResourceWriterB(probe: probe))

    coordinator.runSchedule(.update)

    #expect(!probe.hadViolation)

    let counter = coordinator[resource: SharedCounterResource.self]
    #expect(counter.value == 2)
}

@Test func resourceAccessorReturnsStoredValue() {
    struct LocalResource: Sendable {
        var value: Int
    }

    let coordinator = Coordinator()
    coordinator.addRessource(LocalResource(value: 7))

    var stored: LocalResource = coordinator.resource()
    #expect(stored.value == 7)

    stored.value = 42
    coordinator[resource: LocalResource.self] = stored

    let updated: LocalResource = coordinator.resource()
    #expect(updated.value == 42)
}

@Test func resourceChangeTrackingDetectsUpdates() {
    struct CounterResource: Sendable {
        var value: Int
    }

    let coordinator = Coordinator()
    coordinator.addRessource(CounterResource(value: 0))

    let snapshot = coordinator.makeResourceVersionSnapshot()
    #expect(coordinator.updatedResources(since: snapshot).isEmpty)
    #expect(coordinator.resourceUpdated(CounterResource.self, since: snapshot) == false)

    var counter = coordinator[resource: CounterResource.self]
    counter.value = 42
    coordinator[resource: CounterResource.self] = counter

    let updatedKeys = Set(coordinator.updatedResources(since: snapshot))
    #expect(updatedKeys.contains(ResourceKey(CounterResource.self)))
    #expect(coordinator.resourceUpdated(CounterResource.self, since: snapshot))

    let updatedCounter = coordinator.resourceIfUpdated(CounterResource.self, since: snapshot)
    #expect(updatedCounter?.value == 42)

    let snapshotAfterUpdate = coordinator.makeResourceVersionSnapshot()
    #expect(coordinator.updatedResources(since: snapshotAfterUpdate).isEmpty)
    #expect(coordinator.resourceIfUpdated(CounterResource.self, since: snapshotAfterUpdate) == nil)
}

@Test func queryPerformParallelRespectsFilteringAndMutatesOnce() {
    struct ParallelMarker: Component, Sendable {
        static let componentTag = ComponentTag.makeTag()

        init() {}
    }

    struct ParallelBlocker: Component, Sendable {
        static let componentTag = ComponentTag.makeTag()

        init() {}
    }

    let readQuery = Query {
        WithEntityID.self
        Transform.self
        With<ParallelMarker>.self
        Without<ParallelBlocker>.self
    }

    let writeQuery = Query {
        WithEntityID.self
        Write<Transform>.self
        With<ParallelMarker>.self
        Without<ParallelBlocker>.self
    }

    let coordinator = Coordinator()
    let coreCount = max(2, ProcessInfo.processInfo.processorCount)
    var included: [Entity.ID] = []
    for _ in 0..<(coreCount * 2) {
        included.append(
            coordinator.spawn(
                Transform(position: .zero, rotation: .zero, scale: .zero),
                ParallelMarker()
            )
        )
    }

    let excludedID = coordinator.spawn(
        Transform(position: .zero, rotation: .zero, scale: .zero),
        ParallelMarker(),
        ParallelBlocker()
    )

    let missingMarkerID = coordinator.spawn(
        Transform(position: .zero, rotation: .zero, scale: .zero)
    )

    _ = coordinator.spawn(ParallelMarker())

    var expected = Set<Entity.ID>()
    readQuery(coordinator) { (id: Entity.ID, _: Transform) in
        expected.insert(id)
    }

    #expect(expected == Set(included))

    let invocationCount = ManagedAtomic<Int>(0)
    let results = Mutex<Set<Entity.ID>>(Set())

    writeQuery.performParallel(coordinator) { (id: Entity.ID, transform: Write<Transform>) in
        transform.position.x += 1
        _ = results.withLock { $0.insert(id) }
        invocationCount.wrappingIncrement(ordering: .relaxed)
    }

    let parallelIDs = results.withLock { $0 }
    #expect(parallelIDs == expected)
    #expect(invocationCount.load(ordering: .relaxed) == expected.count)

    let transformPairs = Array(Query { WithEntityID.self; Transform.self }.fetchAll(coordinator))
    let transformsByID = Dictionary(uniqueKeysWithValues: transformPairs)

    for id in included {
        #expect(transformsByID[id]?.position.x ?? Float(-1) == Float(1))
    }

    #expect(transformsByID[excludedID]?.position.x ?? Float(-1) == Float(0))
    #expect(transformsByID[missingMarkerID]?.position.x ?? Float(-1) == Float(0))
}

@Test func queryPerformParallelOnContextProcessesAllEntities() {
    let query = Query {
        Write<Transform>.self
    }

    let coordinator = Coordinator()
    let entityCount = max(2, ProcessInfo.processInfo.processorCount) * 2

    for _ in 0..<entityCount {
        coordinator.spawn(
            Transform(position: .zero, rotation: .zero, scale: .zero)
        )
    }

    let invocationCount = ManagedAtomic<Int>(0)
    let context = QueryContext(coordinator: coordinator)

    query.performParallel(context) { (transform: Write<Transform>) in
        transform.position.x += 1
        invocationCount.wrappingIncrement(ordering: .relaxed)
    }

    #expect(invocationCount.load(ordering: .relaxed) == entityCount)

    let transforms = Array(Query { Transform.self }.fetchAll(coordinator))
    #expect(transforms.count == entityCount)
    #expect(transforms.allSatisfy { $0.position.x == Float(1) })
}

@Test func mainScheduleRunsAllStages() {
    struct StageRecorder<Tag>: System {
        nonisolated(unsafe) static var id: SystemID {
            SystemID(name: "StageRecorder_\(String(describing: Tag.self))")
        }

        var metadata: SystemMetadata { Self.metadata(from: []) }

        let onRun: () -> Void

        func run(context: Components.QueryContext, commands: inout Components.Commands) {
            onRun()
        }
    }

    final class CounterBox {
        let value = ManagedAtomic<Int>(0)
    }

    enum PreStartupTag {}
    enum StartupTag {}
    enum PostStartupTag {}
    enum FirstTag {}
    enum PreUpdateTag {}
    enum FixedFirstTag {}
    enum FixedPreUpdateTag {}
    enum FixedUpdateTag {}
    enum FixedPostUpdateTag {}
    enum FixedLastTag {}
    enum UpdateTag {}
    enum SpawnSceneTag {}
    enum PostUpdateTag {}
    enum LastTag {}

    let coordinator = Coordinator()
    let order = Mutex<[ScheduleLabel]>([])

    func register<Tag>(label: ScheduleLabel, tag _: Tag.Type, counter: CounterBox) {
        coordinator.addSystem(label, system: StageRecorder<Tag> {
            let previous = counter.value.load(ordering: .relaxed)
            if previous == 0 {
                order.withLock { $0.append(label) }
            }
            counter.value.wrappingIncrement(ordering: .relaxed)
        })
    }

    let preStartup = CounterBox()
    let startup = CounterBox()
    let postStartup = CounterBox()
    let first = CounterBox()
    let preUpdate = CounterBox()
    let fixedFirst = CounterBox()
    let fixedPreUpdate = CounterBox()
    let fixedUpdate = CounterBox()
    let fixedPostUpdate = CounterBox()
    let fixedLast = CounterBox()
    let update = CounterBox()
    let spawnScene = CounterBox()
    let postUpdate = CounterBox()
    let last = CounterBox()

    register(label: .preStartup, tag: PreStartupTag.self, counter: preStartup)
    register(label: .startup, tag: StartupTag.self, counter: startup)
    register(label: .postStartup, tag: PostStartupTag.self, counter: postStartup)
    register(label: .first, tag: FirstTag.self, counter: first)
    register(label: .preUpdate, tag: PreUpdateTag.self, counter: preUpdate)
    register(label: .fixedFirst, tag: FixedFirstTag.self, counter: fixedFirst)
    register(label: .fixedPreUpdate, tag: FixedPreUpdateTag.self, counter: fixedPreUpdate)
    register(label: .fixedUpdate, tag: FixedUpdateTag.self, counter: fixedUpdate)
    register(label: .fixedPostUpdate, tag: FixedPostUpdateTag.self, counter: fixedPostUpdate)
    register(label: .fixedLast, tag: FixedLastTag.self, counter: fixedLast)
    register(label: .update, tag: UpdateTag.self, counter: update)
    register(label: .spawnScene, tag: SpawnSceneTag.self, counter: spawnScene)
    register(label: .postUpdate, tag: PostUpdateTag.self, counter: postUpdate)
    register(label: .last, tag: LastTag.self, counter: last)

    MainSystem.reset()

    var fixedClock = coordinator[resource: FixedClock.self]
    fixedClock.timeStep = 0.25
    coordinator[resource: FixedClock.self] = fixedClock

    func advanceWorld(by amount: Double) {
        coordinator[resource: WorldClock.self] = coordinator[resource: WorldClock.self].advancing(by: amount)
    }

    advanceWorld(by: 0.25)
    coordinator.run()

    advanceWorld(by: 0.25)
    coordinator.run()

    let firstRunOrder = order.withLock { $0 }
    #expect(firstRunOrder == [
        .preStartup,
        .startup,
        .postStartup,
        .first,
        .preUpdate,
        .fixedFirst,
        .fixedPreUpdate,
        .fixedUpdate,
        .fixedPostUpdate,
        .fixedLast,
        .update,
        .spawnScene,
        .postUpdate,
        .last
    ])

    #expect(preStartup.value.load(ordering: .relaxed) == 1)
    #expect(startup.value.load(ordering: .relaxed) == 1)
    #expect(postStartup.value.load(ordering: .relaxed) == 1)
    #expect(first.value.load(ordering: .relaxed) == 2)
    #expect(preUpdate.value.load(ordering: .relaxed) == 2)
    #expect(fixedFirst.value.load(ordering: .relaxed) == 2)
    #expect(fixedPreUpdate.value.load(ordering: .relaxed) == 2)
    #expect(fixedUpdate.value.load(ordering: .relaxed) == 2)
    #expect(fixedPostUpdate.value.load(ordering: .relaxed) == 2)
    #expect(fixedLast.value.load(ordering: .relaxed) == 2)
    #expect(update.value.load(ordering: .relaxed) == 2)
    #expect(spawnScene.value.load(ordering: .relaxed) == 2)
    #expect(postUpdate.value.load(ordering: .relaxed) == 2)
    #expect(last.value.load(ordering: .relaxed) == 2)
}

@Test func customScheduleExecution() {
    struct CustomSystem: System {
        static let id = SystemID(name: "CustomSystem")
        var metadata: SystemMetadata { Self.metadata(from: []) }

        let counter: ManagedAtomic<Int>

        func run(context: Components.QueryContext, commands: inout Components.Commands) {
            counter.wrappingIncrement(ordering: .relaxed)
        }
    }

    let customLabel = ScheduleLabel()
    let coordinator = Coordinator()
    let counter = ManagedAtomic<Int>(0)

    coordinator.addSchedule(Schedule(label: customLabel))
    coordinator.addSystem(customLabel, system: CustomSystem(counter: counter))

    coordinator.runSchedule(customLabel)

    coordinator.update(customLabel) { schedule in
        schedule.executor = MultiThreadedExecutor()
    }

    coordinator.runSchedule(customLabel)

    #expect(counter.load(ordering: .relaxed) == 2)
}

@Test func testManyComponents() async {
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
        for _ in 0..<200 {
            coordinator.spawn(mockComponent)
        }
        for _ in 0..<200 {
            let entity = coordinator.spawn()
            for otherComponentNumber in 10..<componentNumber {
                MockComponent.componentTag = ComponentTag(rawValue: otherComponentNumber)
                coordinator.add(mockComponent, to: entity)
            }
        }
    }
    for _ in 0..<100 {
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

    await confirmation(expectedCount: 100) { confirm in
        query(coordinator) { com1, com2, com3 in
            com1.numberWang = com2.numberWang * com3.numberWang * com2.numberWang
            confirm()
        }
    }
}

@Test func addRemove() throws {
    let coordinator = Coordinator()
    for _ in 0..<100 {
        coordinator.spawn(Person())
    }
    let all = Array(Query { WithEntityID.self; Person.self }.fetchAll(coordinator))
    #expect(all.count == 100)
    for i in 0..<50 {
        coordinator.remove(Person.self, from: all[i].0)
    }

    #expect(Array(Query { WithEntityID.self; Person.self }.fetchAll(coordinator)).count == 50)
}

@Test func doubleAddRemove() throws {
    let coordinator = Coordinator()
    for _ in 0..<100 {
        coordinator.spawn(Person())
    }
    let all = Array(Query { WithEntityID.self; Person.self }.fetchAll(coordinator))
    #expect(all.count == 100)
    for i in 0..<50 {
        coordinator.add(Person(), to: all[i].0)
    }
    #expect(Array(Query { WithEntityID.self; Person.self }.fetchAll(coordinator)).count == 100)
}

@Test func combined() async throws {
    let query = Query {
        WithEntityID.self
        Write<Transform>.self
        With<Gravity>.self
        Without<RigidBody>.self
    }

    let coordinator = Coordinator()

    let expectedID = coordinator.spawn(
        Transform(position: .zero, rotation: .zero, scale: .zero),
        Gravity(force: Vector3(x: 1, y: 1, z: 1))
    )

    for _ in 0..<100 {
        coordinator.spawn(
            Transform(position: .zero, rotation: .zero, scale: .zero)
        )
    }

    for _ in 0..<100 {
        coordinator.spawn(
            Transform(position: .zero, rotation: .zero, scale: .zero),
            Gravity(force: Vector3(x: 1, y: 1, z: 1)),
            RigidBody(velocity: .zero, acceleration: .zero)
        )
    }

    for _ in 0..<100 {
        coordinator.spawn(
            Gravity(force: Vector3(x: 1, y: 1, z: 1))
        )
    }

    for _ in 0..<100 {
        coordinator.spawn(
            RigidBody(velocity: .zero, acceleration: .zero)
        )
    }

    for _ in 0..<100 {
        coordinator.spawn(
            Transform(position: .zero, rotation: .zero, scale: .zero),
            RigidBody(velocity: .zero, acceleration: .zero)
        )
    }

    for _ in 0..<100 {
        coordinator.spawn(
            Gravity(force: Vector3(x: 1, y: 1, z: 1)),
            RigidBody(velocity: .zero, acceleration: .zero)
        )
    }

    #expect(query(fetchOne: coordinator)?.0 == expectedID)
    #expect(Array(query(fetchAll: coordinator)).map { $0.0 } == [expectedID])
    await confirmation(expectedCount: 1) { confirmation in
        query(coordinator) { (_: Entity.ID, _: Write<Transform>) in
            confirmation()
        }
    }
    await confirmation(expectedCount: 1) { confirmation in
        query(parallel: coordinator) { (_: Entity.ID, _: Write<Transform>) in
            confirmation()
        }
    }
}

@Test func write() throws {
    let query = Query {
        Write<Transform>.self
        Gravity.self
    }

    #expect(query.backstageComponents == [])
    #expect(query.excludedComponents == [])
    #expect(query.signature == ComponentSignature(Transform.componentTag, Gravity.componentTag))

    let coordinator = Coordinator()

    coordinator.spawn(
        Transform(position: .zero, rotation: .zero, scale: .zero),
        Gravity(force: Vector3(x: 1, y: 1, z: 1))
    )

    query(coordinator) { (transform: Write<Transform>, gravity: Gravity) in
        transform.position.x += gravity.force.x
    }

    let transform = try #require(Query { Transform.self }.fetchOne(coordinator))
    #expect(transform.position == Vector3(x: 1, y: 0, z: 0))
}

@Test func with() throws {
    let query = Query {
        Transform.self
        With<Gravity>.self
    }

    #expect(query.backstageComponents == [Gravity.componentTag])
    #expect(query.excludedComponents == [])
    #expect(query.signature == ComponentSignature(Transform.componentTag, Gravity.componentTag))

    let coordinator = Coordinator()

    coordinator.spawn(
        Transform(position: .zero, rotation: .zero, scale: .zero)
    )

    #expect(query(fetchOne: coordinator) == nil)
}

@Test func without() throws {
    let query = Query {
        Transform.self
        Without<Gravity>.self
    }

    #expect(query.backstageComponents == [])
    #expect(query.excludedComponents == [Gravity.componentTag])
    #expect(query.signature == ComponentSignature(Transform.componentTag))

    let coordinator = Coordinator()

    coordinator.spawn(
        Transform(position: .zero, rotation: .zero, scale: .zero),
        Gravity(force: Vector3(x: 1, y: 1, z: 1))
    )

    #expect(query(fetchOne: coordinator) == nil)
}

@Test func withoutNotExisting() throws {
    let query = Query {
        Transform.self
        Without<Gravity>.self
    }

    #expect(query.backstageComponents == [])
    #expect(query.excludedComponents == [Gravity.componentTag])
    #expect(query.signature == ComponentSignature(Transform.componentTag))

    let coordinator = Coordinator()

    coordinator.spawn(
        Transform(position: .zero, rotation: .zero, scale: .zero)
    )

    #expect(query(fetchOne: coordinator) == Transform(position: .zero, rotation: .zero, scale: .zero))
}

@Test func iterAll() throws {
    let coordinator = Coordinator()

    for _ in 0..<1_000 {
        coordinator.spawn(
            Transform(position: .zero, rotation: .zero, scale: .zero),
            Gravity(force: Vector3(x: 1, y: 1, z: 1))
        )
    }

    let transforms = Query {
        Write<Transform>.self
    }
    .unsafeFetchAllWritable(coordinator)

    func elementTypeIsWriteTransform<S>(_: S) where S: Sequence, S.Element == Write<Transform> {}
    elementTypeIsWriteTransform(transforms)

    #expect(Array(transforms).count == 1_000)

    let multiComponents: LazyWritableQuerySequence<Write<Transform>, Gravity> = Query {
        Write<Transform>.self
        Gravity.self
    }
    .unsafeFetchAllWritable(coordinator)

    func elementTypeIsWriteTransformGravity<S>(_: S) where S: Sequence, S.Element == (Write<Transform>, Gravity) {}
    elementTypeIsWriteTransformGravity(multiComponents)

    #expect(Array(multiComponents).count == 1_000)
}

@Test func iter() throws {
    let coordinator = Coordinator()

    for _ in 0..<100 {
        coordinator.spawn(
            Transform(position: .zero, rotation: .zero, scale: .zero),
            Gravity(force: Vector3(x: 1, y: 1, z: 1))
        )
    }

    let query = Query {
        Write<Transform>.self
        Gravity.self
    }

    let transforms = query.unsafeFetchAllWritable(coordinator)

    var iterCount = 0
    for (transform, gravity) in transforms {
        transform.position.x += gravity.force.x
        iterCount += 1
    }

    var performCount = 0
    query(coordinator) { transform, gravity in
        transform.position.x += gravity.force.x
        performCount += 1
    }

    #expect(iterCount == performCount)
}

@Test func queryExecutionVariants() throws {
    struct Counter: Component, Sendable, Equatable {
        static let componentTag = ComponentTag.makeTag()

        var value: Int
    }

    let coordinator = Coordinator()
    let baseValues = Array(0..<32)
    for value in baseValues {
        coordinator.spawn(Counter(value: value))
    }

    let query = Query {
        Write<Counter>.self
    }

    var sequentialVisit: [Int] = []
    query(preloaded: coordinator) { (counter: Write<Counter>) in
        sequentialVisit.append(counter.value)
        counter.value += 10
    }

    #expect(sequentialVisit == baseValues)

    let afterPreloaded = Array(Query { Counter.self }.fetchAll(coordinator).map(\.value))
    #expect(afterPreloaded == baseValues.map { $0 + 10 })

    let preloadedParallelCount = ManagedAtomic<Int>(0)
    query(preloadedParallel: coordinator) { (counter: Write<Counter>) in
        counter.value += 1
        preloadedParallelCount.wrappingIncrement(ordering: .relaxed)
    }

    #expect(preloadedParallelCount.load(ordering: .relaxed) == baseValues.count)

    let afterPreloadedParallel = Array(Query { Counter.self }.fetchAll(coordinator).map(\.value))
    #expect(afterPreloadedParallel == baseValues.map { $0 + 11 })

    let contextParallelCount = ManagedAtomic<Int>(0)
    let context = coordinator.queryContext
    query(parallel: context) { (counter: Write<Counter>) in
        counter.value += 1
        contextParallelCount.wrappingIncrement(ordering: .relaxed)
    }

    #expect(contextParallelCount.load(ordering: .relaxed) == baseValues.count)

    let finalValues = Array(Query { Counter.self }.fetchAll(coordinator).map(\.value))
    #expect(finalValues == baseValues.map { $0 + 12 })
}

@Test func queryCombinationsCoverAllPairs() {
    struct PairComponent: Component, Sendable {
        static let componentTag = ComponentTag.makeTag()

        var value: Int
    }

    let coordinator = Coordinator()
    let values = [10, 20, 30, 40]
    for value in values {
        coordinator.spawn(PairComponent(value: value))
    }

    let query = Query {
        WithEntityID.self
        PairComponent.self
    }

    var seenPairs: Set<String> = []
    var invocationCount = 0
    query(combinations: coordinator) { lhs, rhs in
        let (lhsID, lhsComponent) = lhs.values
        let (rhsID, rhsComponent) = rhs.values

        #expect(lhsID != rhsID)

        let (minValue, maxValue) = lhsComponent.value < rhsComponent.value
            ? (lhsComponent.value, rhsComponent.value)
            : (rhsComponent.value, lhsComponent.value)

        seenPairs.insert("\(minValue)-\(maxValue)")
        invocationCount += 1
    }

    let expectedPairs = values.count * (values.count - 1) / 2
    #expect(invocationCount == expectedPairs)
    #expect(seenPairs.count == expectedPairs)
}

@Test func fetchAll() throws {
    let coordinator = Coordinator()

    for _ in 0..<1_000 {
        coordinator.spawn(
            Transform(position: .zero, rotation: .zero, scale: .zero),
            Gravity(force: Vector3(x: 1, y: 1, z: 1))
        )
    }

    let transforms = Query {
        Write<Transform>.self
    }
    .fetchAll(coordinator)

    func elementTypeIsTransform<S>(_: S) where S: Sequence, S.Element == Transform {}
    elementTypeIsTransform(transforms)

    #expect(Array(transforms).count == 1_000)

    let multiComponents: LazyQuerySequence<Write<Transform>, Gravity> = Query {
        Write<Transform>.self
        Gravity.self
    }
    .fetchAll(coordinator)

    func elementTypeIsTransformGravity<S>(_: S) where S: Sequence, S.Element == (Transform, Gravity) {}
    elementTypeIsTransformGravity(multiComponents)

    #expect(Array(multiComponents).count == 1_000)
}

@Test func fetchOne() {
    let coordinator = Coordinator()

    for _ in 0..<1_000 {
        coordinator.spawn(
            Transform(position: .zero, rotation: .zero, scale: .zero),
            Gravity(force: Vector3(x: 1, y: 1, z: 1))
        )
    }
    let expectedEntityID = coordinator.spawn(RigidBody(velocity: Vector3(x: 1, y: 2, z: 3), acceleration: .zero))

    let fetchResult = Query {
        WithEntityID.self
        RigidBody.self
    }
    .fetchOne(coordinator)

    #expect(fetchResult?.0 == expectedEntityID)
    #expect(fetchResult?.1 == RigidBody(velocity: Vector3(x: 1, y: 2, z: 3), acceleration: .zero))
}

@Test func withEntityID() async throws {
    let coordinator = Coordinator()
    let expectedID = coordinator.spawn(Transform(position: .zero, rotation: .zero, scale: .zero))
    coordinator.spawn(RigidBody(velocity: .zero, acceleration: .zero))

    let query = Query {
        WithEntityID.self
        Transform.self
    }

    await confirmation(expectedCount: 1) { confirmation in
        query(coordinator) { (entityID: Entity.ID, _: Transform) in
            #expect(entityID == expectedID)
            confirmation()
        }
    }
    await confirmation(expectedCount: 1) { confirmation in
        query(parallel: coordinator) { (entityID: Entity.ID, _: Transform) in
            #expect(entityID == expectedID)
            confirmation()
        }
    }
    #expect(query(fetchOne: coordinator)?.0 == expectedID)

    let all = Array(query(fetchAll: coordinator))
    #expect(all.count == 1)
    #expect(all[0].0 == expectedID)
    #expect(all[0].1 == Transform(position: .zero, rotation: .zero, scale: .zero))
}

@Test
func testReuseSlot() async throws {
    let coordinator = Coordinator()
    let entityA = coordinator.spawn(Gravity(force: .zero))
    coordinator.destroy(entityA)
    let entityB = coordinator.spawn(Gravity(force: .zero))

    // Destroyed slot gets recycled with new generation:
    #expect(entityA.slot == entityB.slot)
    #expect(entityA.generation != entityB.generation)

    // Using the old ID is ignored:
    coordinator.remove(Gravity.self, from: entityA)
    #expect(Query { Gravity.self }.fetchOne(coordinator) != nil)

    // Using the current ID works:
    coordinator.remove(Gravity.self, from: entityB)
    #expect(Query { Gravity.self }.fetchOne(coordinator) == nil)
}

@Test func entityIDs() {
    var coordinator = Coordinator()

    #expect(coordinator.indices.archetype.isEmpty)
    #expect(coordinator.indices.freeIDs.isEmpty)
    #expect(coordinator.indices.generation.isEmpty)
    #expect(coordinator.indices.nextID.rawValue == 0)

    let id1 = coordinator.spawn()
    let id2 = coordinator.spawn()

    #expect(id1 != id2)
    #expect(coordinator.indices.archetype.isEmpty)
    #expect(coordinator.indices.freeIDs.isEmpty)
    #expect(coordinator.indices.generation == [1, 1])
    #expect(coordinator.indices.nextID.rawValue == 2)
    #expect(id1.generation == 1)
    #expect(id2.generation == 1)

    coordinator.destroy(id1)

    #expect(coordinator.indices.archetype.isEmpty)
    #expect(coordinator.indices.freeIDs == [id1.slot])
    #expect(coordinator.indices.generation == [2, 1])
    #expect(coordinator.indices.nextID.rawValue == 2)

    let id3 = coordinator.spawn()

    #expect(id3.slot == id1.slot)
    #expect(id3.generation != id1.generation)
    #expect(id3.generation == 3)
    #expect(coordinator.indices.archetype.isEmpty)
    #expect(coordinator.indices.freeIDs == [])
    #expect(coordinator.indices.generation == [3, 1])
    #expect(coordinator.indices.nextID.rawValue == 2)
}

@Test func memory() throws {
    let coordinator = Coordinator()

    for i in 0..<500_000 {
        coordinator.spawn(
            Transform(
                position: Vector3(x: Float(i), y: Float(i), z: Float(i)),
                rotation: .zero,
                scale: .zero
            ),
            Gravity(force: Vector3(x: Float(-i), y: Float(-i), z: Float(-i)))
        )
    }

    let query = Query {
        Transform.self
        Gravity.self
    }

    var index = 0
    query(coordinator) { transform, gravity in
        #expect(transform.position == Vector3(x: Float(index), y: Float(index), z: Float(index)))
        #expect(gravity.force == Vector3(x: Float(-index), y: Float(-index), z: Float(-index)))
        index += 1
    }

//    index = 0
//    for (transform, gravity) in query.fetchAll(&coordinator) {
//        #expect(transform.position == Vector3(x: Float(index), y: Float(index), z: Float(index)))
//        #expect(gravity.force == Vector3(x: Float(-index), y: Float(-index), z: Float(-index)))
//        index += 1
//    }

//    index = 0
//    let stored = Array(query.fetchAll(&coordinator))
//    for (transform, gravity) in stored {
//        #expect(transform.position == Vector3(x: Float(index), y: Float(index), z: Float(index)))
//        #expect(gravity.force == Vector3(x: Float(-index), y: Float(-index), z: Float(-index)))
//        index += 1
//    }
}

@Test func virtualComponent() async throws {
    let coordinator = Coordinator()

    coordinator.spawn(Transform(position: Vector3(x: 1, y: 1, z: 1), rotation: .zero, scale: Vector3(x: 1, y: 1, z: 1)))
    let expectedID = coordinator.spawn(Transform(position: Vector3(x: -1, y: -1, z: -1), rotation: .zero, scale: Vector3(x: -1, y: -1, z: -1)))

    let query = Query {
        WithEntityID.self
        Downward.self
    }

    await confirmation(expectedCount: 1) { confirmation in
        query(coordinator) { entityID, downward in
            if downward.isDownward {
                #expect(entityID == expectedID)
                confirmation()
            }
        }
    }

    #expect(Array(query.fetchAll(coordinator)).filter { $0.1.isDownward }.map { $0.0 } == [expectedID] )
}

@Test func testQueryEmpty() {
    let coordinator = Coordinator()
    let expectedEntityID = coordinator.spawn()
    coordinator.spawn(Transform(position: .zero, rotation: .zero, scale: .zero))
    let empty = Query< >.emptyEntities(coordinator)
    #expect(empty == [expectedEntityID])
}

@Test func optionalQueryFetchesPresentAndMissingComponents() throws {
    let coordinator = Coordinator()

    let entityWithPerson = coordinator.spawn(Person())
    let entityWithoutPerson = coordinator.spawn()

    let query = Query {
        WithEntityID.self
        Optional<Person>.self
    }

    #expect(!query.signature.contains(Person.componentTag))
    #expect(!query.readOnlySignature.contains(Person.componentTag))

    var results: [Entity.ID: Person?] = [:]
    query(coordinator) { (id: Entity.ID, person: Person?) in
        results[id] = person
    }

    let withPerson = try #require(results[entityWithPerson])
    let withoutPerson = try #require(results[entityWithoutPerson])

    #expect(withPerson != nil)
    #expect(withoutPerson == nil)
    #expect(results.count == 2)
}

@Test func testOptionalWrite() {
    struct OptionalContaining: Component, Equatable {
        static let componentTag = ComponentTag.makeTag()

        var optionalValue: Int?
    }

    let coordinator = Coordinator()
    coordinator.spawn(Person(), OptionalContaining(optionalValue: 42))

    let query = Query {
        OptionalWrite<OptionalContaining>.self
        With<Person>.self
    }

    query(coordinator) { (optional: OptionalWrite<OptionalContaining>) in
        optional.wrapped?.optionalValue = nil
    }

    let all = Array(query.fetchAll(coordinator))
    #expect(all == [OptionalContaining(optionalValue: nil)])
}

@Test func testOptionalWriteNone() {
    struct OptionalContaining: Component, Equatable {
        static let componentTag = ComponentTag.makeTag()

        var optionalValue: Int?
    }

    let coordinator = Coordinator()
    coordinator.spawn(Person())

    let query = Query {
        OptionalWrite<OptionalContaining>.self
        With<Person>.self
    }

    var calls = 0
    query(coordinator) { (optional: OptionalWrite<OptionalContaining>) in
        optional.wrapped?.optionalValue = nil
        calls += 1
    }

    #expect(calls == 1)
    let all = Array(query.fetchAll(coordinator))
    #expect(all == [(nil)])
}

@Test func testOptionalWriteNoneMixed() {
    struct OptionalContaining: Component, Hashable {
        static let componentTag = ComponentTag.makeTag()

        var optionalValue: Int?
    }

    let coordinator = Coordinator()
    coordinator.spawn(Person())
    coordinator.spawn(Person(), OptionalContaining(optionalValue: 42))

    let query = Query {
        OptionalWrite<OptionalContaining>.self
        With<Person>.self
    }

    var calls = 0
    query(coordinator) { (optional: OptionalWrite<OptionalContaining>) in
        optional.wrapped?.optionalValue = nil
        calls += 1
    }

    #expect(calls == 2)
    let all = Array(query.fetchAll(coordinator))
    #expect(Set(all) == Set([nil, OptionalContaining(optionalValue: nil)]))
}

@Test func querySignaturesHandleOptionalComponents() {
    typealias TestQuery = Query<
        Transform,
        Optional<Gravity>,
        Write<RigidBody>,
        OptionalWrite<Shape>
    >

    let readWithoutOptionals = TestQuery.makeReadSignature(backstageComponents: [], includeOptionals: false)
    #expect(readWithoutOptionals.contains(Transform.componentTag))
    #expect(!readWithoutOptionals.contains(Gravity.componentTag))
    #expect(!readWithoutOptionals.contains(RigidBody.componentTag))
    #expect(!readWithoutOptionals.contains(Shape.componentTag))

    let readWithOptionals = TestQuery.makeReadSignature(backstageComponents: [], includeOptionals: true)
    #expect(readWithOptionals.contains(Transform.componentTag))
    #expect(readWithOptionals.contains(Gravity.componentTag))
    #expect(!readWithOptionals.contains(RigidBody.componentTag))
    #expect(!readWithOptionals.contains(Shape.componentTag))

    let writeWithoutOptionals = TestQuery.makeWriteSignature(includeOptionals: false)
    #expect(writeWithoutOptionals.contains(RigidBody.componentTag))
    #expect(!writeWithoutOptionals.contains(Shape.componentTag))

    let writeWithOptionals = TestQuery.makeWriteSignature(includeOptionals: true)
    #expect(writeWithOptionals.contains(RigidBody.componentTag))
    #expect(writeWithOptionals.contains(Shape.componentTag))
}

@Test func signature() {
    #expect(ComponentSignature(Transform.componentTag) == ComponentSignature(Transform.componentTag))
    #expect(ComponentSignature(Person.componentTag) == ComponentSignature(Person.componentTag))
    #expect(ComponentSignature(RigidBody.componentTag) == ComponentSignature(RigidBody.componentTag))
    #expect(ComponentSignature(Transform.componentTag) != ComponentSignature(RigidBody.componentTag))

    let a = ComponentSignature(Transform.componentTag, Person.componentTag, RigidBody.componentTag)
    var b = ComponentSignature()
    b.append(RigidBody.componentTag)
    b.append(Person.componentTag)
    b.append(Transform.componentTag)
    #expect(a == b)
}

@Test func queryMetadata() throws {
    let query = Query {
        Write<Health>.self        // Write signature
        OptionalWrite<Shape>.self // Omitted but part of scheduling write
        With<Person>.self         // "signature"
        RigidBody.self            // Read signature
        Without<Gravity>.self     // Excluded signature
        Material?.self            // Omitted but part of scheduling read
        Downward.self             // Read signature (as Transform)
    }

    #expect(query.schedulingMetadata.readSignature == ComponentSignature(RigidBody.componentTag, Transform.componentTag, Material.componentTag))
    #expect(query.readOnlySignature == ComponentSignature(RigidBody.componentTag, Transform.componentTag))

    #expect(query.schedulingMetadata.writeSignature == ComponentSignature(Health.componentTag, Shape.componentTag))
    #expect(query.writeSignature == ComponentSignature(Health.componentTag))

    #expect(query.schedulingMetadata.excludedSignature == ComponentSignature(Gravity.componentTag))

    #expect(query.signature == ComponentSignature(Health.componentTag, Person.componentTag, RigidBody.componentTag, Transform.componentTag))
    #expect(query.backstageSignature == ComponentSignature(Person.componentTag))
    #expect(query.excludedSignature == ComponentSignature(Gravity.componentTag))
}

@Test func optional() async throws {
    let coordinator = Coordinator()
    coordinator.spawn(Person())
    coordinator.spawn(Person(), Material())
    let query = Query {
        Person.self
        Material?.self
    }
    await confirmation(expectedCount: 1) { nilConfirmation in
        await confirmation(expectedCount: 1) { nonNilConfirmation in
            query(coordinator) { person, material in
                if material == nil {
                    nilConfirmation()
                }
                if material != nil {
                    nonNilConfirmation()
                }
            }
        }
    }
}

@Test func writeOptional() async throws {
    let coordinator = Coordinator()
    coordinator.spawn(Person())
    coordinator.spawn(Person(), Gravity(force: .zero))
    let query = Query {
        Person.self
        OptionalWrite<Gravity>.self
    }

    query(coordinator) { person, gravity in
        gravity.wrapped?.force.x += 1
    }

    let all = Array(Query { Gravity.self }.fetchAll(coordinator))
    #expect(all == [Gravity(force: Vector3(x: 1, y: 0, z: 0))])
}

public struct Downward: Component, Sendable {
    public static var componentTag: ComponentTag { Transform.componentTag }
    public typealias QueriedComponent = Transform

    let isDownward: Bool

    public init(isDownward: Bool) {
        print("is", isDownward)
        self.isDownward = isDownward
    }

    @inlinable @inline(__always)
    public static func makeResolved(access: TypedAccess<Self>, entityID: Entity.ID) -> Downward {
        print("called")
        return Downward(isDownward: access.access(entityID).value.position.y < 0)
    }

    @inlinable @inline(__always)
    public static func makeReadOnlyResolved(access: TypedAccess<Self>, entityID: Entity.ID) -> Downward {
        print("called readonly", entityID, access.access(entityID).value.position.y)
        return Downward(isDownward: access.access(entityID).value.position.y < 0)
    }

    @inlinable @inline(__always)
    public static func makeResolvedDense(access: TypedAccess<Self>, denseIndex: Int, entityID: Entity.ID) -> Downward {
        print("called")
        return Downward(isDownward: access.accessDense(denseIndex, entityID: entityID).value.position.y < 0)
    }

    @inlinable @inline(__always)
    public static func makeReadOnlyResolvedDense(access: TypedAccess<Self>, denseIndex: Int, entityID: Entity.ID) -> Downward {
        print("called readonly", entityID, access.accessDense(denseIndex, entityID: entityID).value.position.y)
        return Downward(isDownward: access.accessDense(denseIndex, entityID: entityID).value.position.y < 0)
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

public struct Gravity: Component, Equatable {
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

public struct Shape: Component, Equatable {
    public static let componentTag = ComponentTag.makeTag()

    public var bounds: Vector3

    public init(bounds: Vector3) {
        self.bounds = bounds
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

public struct Health: Component {
    public static let componentTag = ComponentTag.makeTag()

    public var value: Int

    public init(value: Int) {
        self.value = value
    }
}

public struct Material: Component {
    public static let componentTag = ComponentTag.makeTag()
    
    public init() {
    }
}

@Test func groupRebuildMirrorsPrimary() throws {
    let coordinator = Coordinator()

    // Create entities with various component combos
    let e1 = coordinator.spawn(Transform(position: .zero, rotation: .zero, scale: .zero), Gravity(force: .zero), Material()) // match
    let _  = coordinator.spawn(Gravity(force: .zero)) // non-match
    let _  = coordinator.spawn(Transform(position: .zero, rotation: .zero, scale: .zero)) // non-match
    let _  = coordinator.spawn(Transform(position: .zero, rotation: .zero, scale: .zero), Gravity(force: .zero), RigidBody(velocity: .zero, acceleration: .zero), Material()) // excluded
    let e5 = coordinator.spawn(Transform(position: .zero, rotation: .zero, scale: .zero), Gravity(force: .zero), Material()) // match
    let _ = coordinator.spawn(Transform(position: .zero, rotation: .zero, scale: .zero), Gravity(force: .zero)) // lacks Material

    // Build a group that owns Transform + Gravity, requires Material, excludes RigidBody
    // Rebuild group: only e1 and e5 should be packed in front, in the order dictated by primary (Transform)
    let signature = coordinator.addGroup {
        Transform.self
        Gravity.self
        With<Material>.self
        Without<RigidBody>.self
    }

    #expect(coordinator.groupSize(signature) == 2)

    // Verify primary (Transform) packed prefix order == [e1, e5]
    let primaryArray = coordinator.pool[Transform.self]
    let primaryKeys = primaryArray.componentsToEntites
    #expect(primaryKeys.count == 5)
    #expect(primaryKeys[0] == e1.slot)
    #expect(primaryKeys[1] == e5.slot)

    // Verify mirrored order in Gravity storage == [e1, e5]
    let gravityArray = coordinator.pool[Gravity.self]
    let gravityKeys = gravityArray.componentsToEntites
    #expect(gravityKeys.count == 5)
    #expect(gravityKeys[0] == e1.slot)
    #expect(gravityKeys[1] == e5.slot)
}

@Test func groupRebuildOnBackstageAdded() throws {
    let coordinator = Coordinator()

    // Create entities with various component combos
    let e1 = coordinator.spawn(Transform(position: .zero, rotation: .zero, scale: .zero))

    // Build a group that owns Transform + Gravity, requires Material, excludes RigidBody
    // Rebuild group: only e1 and e5 should be packed in front, in the order dictated by primary (Transform)
    let signature = coordinator.addGroup {
        Transform.self
        With<Material>.self
    }

    #expect(coordinator.groupSize(signature) == 0)

    coordinator.add(Material(), to: e1)

    #expect(coordinator.groupSize(signature) == 1)
}

@Test func groupRebuildOnExcludeAdded() throws {
    let coordinator = Coordinator()

    // Create entities with various component combos
    let e1 = coordinator.spawn(Transform(position: .zero, rotation: .zero, scale: .zero))

    // Build a group that owns Transform + Gravity, requires Material, excludes RigidBody
    // Rebuild group: only e1 and e5 should be packed in front, in the order dictated by primary (Transform)
    let signature = coordinator.addGroup {
        Transform.self
        Without<Material>.self
    }

    #expect(coordinator.groupSize(signature) == 1)

    coordinator.add(Material(), to: e1)

    #expect(coordinator.groupSize(signature) == 0)
}

@Test func groupAddOwnedSwapsInAndMirrors() throws {
    let coordinator = Coordinator()

    // Prepare an entity that will become a match when we add an OWNED component (Transform)
    let eA = coordinator.spawn(Gravity(force: .zero), Material()) // has Gravity+Material
    let eB = coordinator.spawn(Transform(position: .zero, rotation: .zero, scale: .zero), Gravity(force: .zero), Material()) // existing match

    let signature = coordinator.addGroup {
        Transform.self
        Gravity.self
        With<Material>.self
        Without<RigidBody>.self
    }

    #expect(coordinator.groupSize(signature) == 1)

    // Add Transform (owned) to eA -> should swap into packed prefix at index 1 in primary and mirror to Gravity
    coordinator.add(Transform(position: .zero, rotation: .zero, scale: .zero), to: eA)

    #expect(coordinator.groupSize(signature) == 2)

    // Check primary order contains eB then eA (based on existing primary order and swap)
    let primaryArray = coordinator.pool[Transform.self]
    let primaryKeys = primaryArray.componentsToEntites
    #expect(primaryKeys.count >= 2)
    // eB was first match after rebuild
    #expect(primaryKeys[0] == eB.slot)
    #expect(primaryKeys[1] == eA.slot)

    // Check mirrored order in Gravity
    let gravityArray = coordinator.pool[Gravity.self]
    let gravityKeys = gravityArray.componentsToEntites
    #expect(gravityKeys.count >= 2)
    #expect(gravityKeys[0] == eB.slot)
    #expect(gravityKeys[1] == eA.slot)
}

@Test func groupRemoveSwapsOutAndMirrors() throws {
    let coordinator = Coordinator()

    // Two matching entities
    let e1 = coordinator.spawn(Transform(position: .zero, rotation: .zero, scale: .zero), Gravity(force: .zero), Material())
    let e2 = coordinator.spawn(Transform(position: .zero, rotation: .zero, scale: .zero), Gravity(force: .zero), Material())

    let signature = coordinator.addGroup {
        Transform.self
        Gravity.self
        With<Material>.self
        Without<RigidBody>.self
    }

    #expect(coordinator.groupSize(signature) == 2)

    // Remove an OWNED component (Gravity) from e1 -> should be swapped out of packed prefix
    coordinator.remove(Gravity.self, from: e1)

    #expect(coordinator.groupSize(signature) == 1)

    // After removal, e2 should occupy index 0 in both storages
    let primaryArray = coordinator.pool[Transform.self]
    let primaryKeys = primaryArray.componentsToEntites
    #expect(primaryKeys.count >= 1)
    #expect(primaryKeys[0] == e2.slot)

    let gravityArray = coordinator.pool[Gravity.self]
    let gravityKeys = gravityArray.componentsToEntites
    #expect(gravityKeys.count >= 1)
    #expect(gravityKeys[0] == e2.slot)
}

@Test func groupRemovePrimarySwapsOutAndMirrors() throws {
    let coordinator = Coordinator()

    // Two matching entities
    let e1 = coordinator.spawn(Transform(position: .zero, rotation: .zero, scale: .zero), Gravity(force: .zero), Material())
    let e2 = coordinator.spawn(Transform(position: .zero, rotation: .zero, scale: .zero), Gravity(force: .zero), Material())

    let signature = coordinator.addGroup {
        Transform.self
        Gravity.self
        With<Material>.self
        Without<RigidBody>.self
    }

    #expect(coordinator.groupSize(signature) == 2)

    // Remove an OWNED component (Gravity) from e1 -> should be swapped out of packed prefix
    coordinator.remove(Transform.self, from: e1)

    #expect(coordinator.groupSize(signature) == 1)

    // After removal, e2 should occupy index 0 in both storages
    let primaryArray = coordinator.pool[Transform.self]
    let primaryKeys = primaryArray.componentsToEntites
    #expect(primaryKeys.count >= 1)
    #expect(primaryKeys[0] == e2.slot)

    let gravityArray = coordinator.pool[Gravity.self]
    let gravityKeys = gravityArray.componentsToEntites
    #expect(gravityKeys.count >= 1)
    #expect(gravityKeys[0] == e2.slot)
}

@Test func testBitSetIteration() {
    let components = ComponentSignature(Transform.componentTag, Material.componentTag, Gravity.componentTag)
    #expect(Set(components.tags) == Set([Transform.componentTag, Material.componentTag, Gravity.componentTag]))
}

@Test func bestGroupSelectionPrefersExactMatches() throws {
    let coordinator = Coordinator()

    let entityWithMaterial = coordinator.spawn(
        Transform(position: .zero, rotation: .zero, scale: .zero),
        Gravity(force: .zero),
        Material()
    )
    let entityWithoutMaterial = coordinator.spawn(
        Transform(position: .zero, rotation: .zero, scale: .zero),
        Gravity(force: .zero)
    )

    let exactSignature = coordinator.addGroup {
        Transform.self
        Gravity.self
        With<Material>.self
    }
    #expect(coordinator.groupSize(exactSignature) == 1)

    _ = coordinator.addGroup {
        With<Transform>.self
    }

    let exactQuery = Query {
        Write<Transform>.self
        Gravity.self
        With<Material>.self
    }

    let exactResult = try #require(coordinator.bestGroup(for: exactQuery.querySignature))
    #expect(exactResult.exact)
    #expect(Set(exactResult.slots) == Set([entityWithMaterial.slot]))
    #expect(exactResult.owned == ComponentSignature(Transform.componentTag, Gravity.componentTag))

    let fallbackQuery = Query {
        Write<Transform>.self
        Gravity.self
    }

    let fallbackResult = try #require(coordinator.bestGroup(for: fallbackQuery.querySignature))
    #expect(!fallbackResult.exact)
    #expect(Set(fallbackResult.slots) == Set([entityWithMaterial.slot, entityWithoutMaterial.slot]))
    #expect(fallbackResult.owned == ComponentSignature())
}

@Test func removeGroupClearsMetadata() throws {
    let coordinator = Coordinator()

    coordinator.spawn(Transform(position: .zero, rotation: .zero, scale: .zero), Gravity(force: .zero))
    coordinator.spawn(Transform(position: .zero, rotation: .zero, scale: .zero), Gravity(force: .zero))

    let signature = coordinator.addGroup {
        Transform.self
        Gravity.self
    }

    #expect(coordinator.groupSize(signature) == 2)

    let query = Query {
        Transform.self
        Gravity.self
    }

    coordinator.removeGroup {
        Transform.self
        Gravity.self
    }

    #expect(coordinator.groupSize(signature) == nil)
    #expect(coordinator.bestGroup(for: query.querySignature) == nil)
}

@Test func owningVsNonOwningGroupMetadata() throws {
    let coordinator = Coordinator()

    let entityA = coordinator.spawn(Transform(position: .zero, rotation: .zero, scale: .zero), Gravity(force: .zero))
    let entityB = coordinator.spawn(Transform(position: .zero, rotation: .zero, scale: .zero), Gravity(force: .zero))

    let owningSignature = coordinator.addGroup {
        Transform.self
        Gravity.self
    }

    let nonOwningSignature = coordinator.addGroup {
        With<Transform>.self
        With<Gravity>.self
    }

    #expect(coordinator.isOwningGroup(owningSignature))
    #expect(!coordinator.isOwningGroup(nonOwningSignature))

    let owning = try #require(coordinator.groupSlotsWithOwned(owningSignature))
    #expect(Set(owning.0) == Set([entityA.slot, entityB.slot]))
    #expect(owning.1 == ComponentSignature(Transform.componentTag, Gravity.componentTag))

    let nonOwning = try #require(coordinator.groupSlotsWithOwned(nonOwningSignature))
    #expect(Set(nonOwning.0) == Set([entityA.slot, entityB.slot]))
    #expect(nonOwning.1 == ComponentSignature())
}

@Test func performGroupFallbackWithoutMatchingGroup() {
    struct SoloComponent: Component, Sendable, Equatable {
        static let componentTag = ComponentTag.makeTag()

        var value: Int
    }

    let coordinator = Coordinator()
    coordinator.spawn(SoloComponent(value: 1))
    coordinator.spawn(SoloComponent(value: 2))

    var visited: [Int] = []
    Query {
        SoloComponent.self
    }.performGroup(coordinator) { (component: SoloComponent) in
        visited.append(component.value)
    }

    #expect(Set(visited) == Set([1, 2]))
    #expect(coordinator.groupSize { SoloComponent.self } == nil)

    let fetched = Array(Query { SoloComponent.self }.fetchAll(coordinator).map(\.value))
    #expect(Set(fetched) == Set([1, 2]))
}

@Test func nonOwningGroup_basic() throws {
    let coordinator = Coordinator()

    // Create entities: two match (T+G, no RB), one excluded (has RB), one missing G
    let e1 = coordinator.spawn(Transform(position: .zero, rotation: .zero, scale: .zero), Gravity(force: .zero))
    let _  = coordinator.spawn(Transform(position: .zero, rotation: .zero, scale: .zero), Gravity(force: .zero), RigidBody(velocity: .zero, acceleration: .zero))
    let _ = coordinator.spawn(Transform(position: .zero, rotation: .zero, scale: .zero))
    let e4 = coordinator.spawn(Transform(position: .zero, rotation: .zero, scale: .zero), Gravity(force: .zero))

    // Build a NON-OWNING group requiring Transform & Gravity, excluding RigidBody
    let sig = coordinator.addGroup {
        With<Transform>.self
        With<Gravity>.self
        Without<RigidBody>.self
    }

    // Group should include e1 and e4 only
    #expect(coordinator.groupSize(sig) == 2)
    let slots = try #require(coordinator.groupSlots(sig))
    #expect(Set(slots) == Set([e1.slot, e4.slot]))

    // Verify performGroup iterates exactly the group members
    var seen = 0
    Query { Transform.self; Gravity.self; Without<RigidBody>.self }.performGroup(coordinator, requireGroup: true) { (_: Transform, _: Gravity) in
        seen += 1
    }
    #expect(seen == 2)

    // Use WithEntityID to ensure IDs resolve correctly on non-owning groups
    var ids: [Entity.ID] = []
    Query { WithEntityID.self; Transform.self; Gravity.self; Without<RigidBody>.self }.performGroup(coordinator, requireGroup: true) { (id: Entity.ID, _: Transform, _: Gravity) in
        ids.append(id)
    }
    #expect(Set(ids.map { $0.slot }) == Set([e1.slot, e4.slot]))
}

@Test func partiallyOwningGroup_withBackstage() throws {
    let coordinator = Coordinator()

    // One entity starts without Material, one with Material
    let eA = coordinator.spawn(Transform(position: .zero, rotation: .zero, scale: .zero))
    coordinator.spawn(Transform(position: .zero, rotation: .zero, scale: .zero), Material())

    // Group owns Transform, requires Material (backstage)
    let sig = coordinator.addGroup {
        Transform.self
        With<Material>.self
    }

    #expect(coordinator.groupSize(sig) == 1)

    // Adding Material to eA should include it in the group incrementally
    coordinator.add(Material(), to: eA)
    #expect(coordinator.groupSize(sig) == 2)

    // performGroup should visit both
    var count = 0
    Query { Transform.self; With<Material>.self }.performGroup(coordinator, requireGroup: true) { (_: Transform) in
        count += 1
    }
    #expect(count == 2)
}

@Test func owningGroup_withEntityID_dense() throws {
    let coordinator = Coordinator()
    let e1 = coordinator.spawn(Transform(position: .zero, rotation: .zero, scale: .zero), Gravity(force: .zero))
    let e2 = coordinator.spawn(Transform(position: .zero, rotation: .zero, scale: .zero), Gravity(force: .zero))

    let sig = coordinator.addGroup {
        Transform.self
        Gravity.self
    }
    #expect(coordinator.groupSize(sig) == 2)

    var collected: [Entity.ID] = []
    Query { WithEntityID.self; Write<Transform>.self; Gravity.self }.performGroup(coordinator, requireGroup: true) { (id: Entity.ID, _: Write<Transform>, _: Gravity) in
        collected.append(id)
    }
    #expect(Set(collected.map { $0.slot }) == Set([e1.slot, e2.slot]))
}

@Test func optionalComponent_withOwningGroupSubset() throws {
    let coordinator = Coordinator()

    // Some entities have Gravity, some do not
    coordinator.spawn(Transform(position: .zero, rotation: .zero, scale: .zero))
    coordinator.spawn(Transform(position: .zero, rotation: .zero, scale: .zero), Gravity(force: .zero))

    // Own only Transform so the group covers all candidates
    let sig = coordinator.addGroup {
        Transform.self
    }
    #expect(coordinator.groupSize(sig) == 2)

    // Query requires Transform, optionally Gravity; should visit both entities
    var optionalStates: [Bool] = []
    // This will find a non-exact group match and it will filter during iteration but with an empty filter.
    // TODO: Query needs to be fixed to optionals are not part of the signatures. Then this will be an exact match with no filtering.
    Query { Transform.self; OptionalWrite<Gravity>.self }.performGroup(coordinator, requireGroup: true) { (_: Transform, g: OptionalWrite<Gravity>) in
        // Record whether gravity is present
        g.wrapped?.force.x += 1
        optionalStates.append(g.wrapped?.force != nil)
    }

    // Expect exactly one with gravity present and one without
    #expect(optionalStates.count == 2)
    #expect(Set(optionalStates) == Set([true, false]))
}

@Test func optionalComponent_withOwningGroupSubset2() throws {
    let coordinator = Coordinator()

    // Some entities have Gravity, some do not
    coordinator.spawn(Transform(position: .zero, rotation: .zero, scale: .zero))
    coordinator.spawn(Transform(position: .zero, rotation: .zero, scale: .zero), Gravity(force: .zero))

    // Own only Transform so the group covers all candidates
    let sig = coordinator.addGroup {
        Transform.self
    }
    #expect(coordinator.groupSize(sig) == 2)

    // Query requires Transform, optionally Gravity; should visit both entities
    var count = 0
    Query { Transform.self; Gravity.self }.performGroup(coordinator, requireGroup: true) { (_: Transform, g: Gravity) in
        // Record whether gravity is present
        count += 1
    }

    // Expect exactly one with gravity present and one without
    #expect(count == 1)
}

@Test func optionalComponent_withOwningGroupSubset3() throws {
    let coordinator = Coordinator()

    // Some entities have Gravity, some do not
    coordinator.spawn(Transform(position: .zero, rotation: .zero, scale: .zero))
    coordinator.spawn(Transform(position: .zero, rotation: .zero, scale: .zero), Gravity(force: .zero))

    // Own only Transform so the group covers all candidates
    let sig = coordinator.addGroup {
        Transform.self
    }
    #expect(coordinator.groupSize(sig) == 2)

    // Query requires Transform, optionally Gravity; should visit both entities
    var count = 0
    Query { Transform.self; Write<Gravity>.self }.performGroup(coordinator, requireGroup: true) { (_: Transform, g: Write<Gravity>) in
        // Record whether gravity is present
        g.force = .zero
        count += 1
    }

    // Expect exactly one with gravity present and one without
    #expect(count == 1)
}

@Test func commandQueueLifecycleOperations() {
    final class CommandCounters {
        let spawnCount = ManagedAtomic<Int>(0)
        let destroyCount = ManagedAtomic<Int>(0)
        let runCount = ManagedAtomic<Int>(0)
        let targetAliveAfterDestroy = ManagedAtomic<Bool>(false)
    }

    struct CommandSystem: System {
        static let id = SystemID(name: "CommandSystem")
        var metadata: SystemMetadata { Self.metadata(from: []) }

        let target: Entity.ID
        let counters: CommandCounters

        func run(context: Components.QueryContext, commands: inout Components.Commands) {
            commands.add(
                component: Transform(
                    position: .zero,
                    rotation: .zero,
                    scale: Vector3(x: 1, y: 1, z: 1)
                ),
                to: target
            )
            commands.add(component: Gravity(force: .zero), to: target)
            commands.remove(component: Gravity.self, from: target)

            commands.run { coordinator in
                counters.runCount.wrappingIncrement(ordering: .relaxed)
                let all = Array(Query { WithEntityID.self; Transform.self }.fetchAll(coordinator))
                let transform = all.first { id, transform in
                    id == target
                }?.1
                #expect(transform?.scale == Vector3(x: 1, y: 1, z: 1))
                let all2 = Array(Query { WithEntityID.self; Gravity.self }.fetchAll(coordinator))
                #expect(all2.allSatisfy { $0.0 != target })
            }

            commands.spawn(
                component: Transform(
                    position: Vector3(x: 1, y: 1, z: 1),
                    rotation: .zero,
                    scale: Vector3(x: 1, y: 1, z: 1)
                )
            ) { coordinator, entity in
                counters.spawnCount.wrappingIncrement(ordering: .relaxed)
                let all = Array(Query { WithEntityID.self; Transform.self }.fetchAll(coordinator))
                let matching = all.first { pair in
                    pair.0 == entity
                }?.1
                #expect(matching?.position == Vector3(x: 1, y: 1, z: 1))
                coordinator.remove(Transform.self, from: entity)
                coordinator.destroy(entity)
                counters.destroyCount.wrappingIncrement(ordering: .relaxed)
            }

            commands.spawn { coordinator, entity in
                counters.spawnCount.wrappingIncrement(ordering: .relaxed)
                coordinator.add(Gravity(force: Vector3(x: 1, y: 1, z: 1)), to: entity)
                coordinator.destroy(entity)
                counters.destroyCount.wrappingIncrement(ordering: .relaxed)
            }

            commands.destroy(target)
            commands.run { coordinator in
                counters.targetAliveAfterDestroy.store(coordinator.isAlive(target), ordering: .relaxed)
                counters.runCount.wrappingIncrement(ordering: .relaxed)
            }
        }
    }

    let coordinator = Coordinator()
    let counters = CommandCounters()
    let target = coordinator.spawn()

    coordinator.addSystem(.update, system: CommandSystem(target: target, counters: counters))
    coordinator.update(.update) { $0.executor = SingleThreadedExecutor() }
    coordinator.runSchedule(.update)

    #expect(!coordinator.isAlive(target))
    #expect(Query { Transform.self }.fetchOne(coordinator) == nil)
    #expect(Query { Gravity.self }.fetchOne(coordinator) == nil)
    #expect(counters.spawnCount.load(ordering: .relaxed) == 2)
    #expect(counters.destroyCount.load(ordering: .relaxed) == 2)
    #expect(counters.runCount.load(ordering: .relaxed) == 2)
    let targetNotAliveAfterDestroy = !counters.targetAliveAfterDestroy.load(ordering: .relaxed)
    #expect(targetNotAliveAfterDestroy)
}

@Test func removeGroupClearsMetadataAndStorage() {
    let coordinator = Coordinator()

    let signature = coordinator.addGroup {
        Transform.self
        With<Gravity>.self
        Without<RigidBody>.self
    }

    #expect(coordinator.groupSize(signature) == 0)

    let entity = coordinator.spawn(
        Transform(
            position: .zero,
            rotation: .zero,
            scale: Vector3(x: 1, y: 1, z: 1)
        ),
        Gravity(force: .zero)
    )

    #expect(coordinator.groupSize(signature) == 1)

    coordinator.removeGroup {
        Transform.self
        With<Gravity>.self
        Without<RigidBody>.self
    }

    #expect(coordinator.groupSize(signature) == nil)

    var visited = 0
    Query {
        WithEntityID.self
        Write<Transform>.self
        Gravity.self
        Without<RigidBody>.self
    }(coordinator) { (id: Entity.ID, transform: Write<Transform>, _: Gravity) in
        #expect(id == entity)
        transform.position.x += 1
        visited += 1
    }

    #expect(visited == 1)

    coordinator.destroy(entity)

    #expect(Query { Transform.self }.fetchOne(coordinator) == nil)
    #expect(Query { Gravity.self }.fetchOne(coordinator) == nil)
}

@Test func destroyingEntityTwiceIsSafe() {
    let coordinator = Coordinator()
    let entity = coordinator.spawn(
        Transform(
            position: Vector3(x: 1, y: 1, z: 1),
            rotation: .zero,
            scale: Vector3(x: 1, y: 1, z: 1)
        )
    )

    coordinator.destroy(entity)
    coordinator.destroy(entity)

    #expect(!coordinator.isAlive(entity))
    #expect(Query { Transform.self }.fetchOne(coordinator) == nil)
}

private struct TestEvent: Event, Equatable {
    let value: Int
}

private final class EventEmitterSystem: System {
    static let id = SystemID(name: "EventEmitterSystem")
    static let counter = ManagedAtomic<Int>(0)

    var metadata: SystemMetadata {
        Self.metadata(from: [], eventAccess: [(EventKey(TestEvent.self), .write)])
    }

    func run(context: QueryContext, commands: inout Commands) {
        let value = Self.counter.loadThenWrappingIncrement(ordering: .relaxed)
        context.send(TestEvent(value: value))
    }

    static func reset() {
        counter.store(0, ordering: .relaxed)
    }
}

private final class EventReaderSystem: System {
    static let id = SystemID(name: "EventReaderSystem")

    private let runAfter: Set<SystemID>
    private(set) var seen: [Int] = []
    private var state = EventReaderState<TestEvent>()

    init(runAfter: Set<SystemID> = []) {
        self.runAfter = runAfter
    }

    var metadata: SystemMetadata {
        SystemMetadata(
            id: Self.id,
            readSignature: ComponentSignature(),
            writeSignature: ComponentSignature(),
            excludedSignature: ComponentSignature(),
            runAfter: runAfter,
            resourceAccess: [],
            eventAccess: [(EventKey(TestEvent.self), .read)]
        )
    }

    func run(context: QueryContext, commands: inout Commands) {
        let events = context.readEvents(TestEvent.self, state: &state)
        guard !events.isEmpty else { return }
        seen.append(contentsOf: events.map(\.value))
    }
}

private final class EventDrainSystem: System {
    static let id = SystemID(name: "EventDrainSystem")

    private let runAfter: Set<SystemID>
    private(set) var drained: [[Int]] = []

    init(runAfter: Set<SystemID> = []) {
        self.runAfter = runAfter
    }

    var metadata: SystemMetadata {
        SystemMetadata(
            id: Self.id,
            readSignature: ComponentSignature(),
            writeSignature: ComponentSignature(),
            excludedSignature: ComponentSignature(),
            runAfter: runAfter,
            resourceAccess: [],
            eventAccess: [(EventKey(TestEvent.self), .drain)]
        )
    }

    func run(context: QueryContext, commands: inout Commands) {
        let drainedEvents = context.drainEvents(TestEvent.self)
        if !drainedEvents.isEmpty {
            drained.append(drainedEvents.map(\.value))
        }
    }
}

@Test func eventsAreDeliveredOnSubsequentRuns() {
    EventEmitterSystem.reset()
    defer { EventEmitterSystem.reset() }
    let coordinator = Coordinator()
    coordinator.update(.update) { schedule in
        schedule.executor = SingleThreadedExecutor()
    }

    let reader = EventReaderSystem(runAfter: [EventEmitterSystem.id])

    coordinator.addSystem(.update, system: EventEmitterSystem())
    coordinator.addSystem(.update, system: reader)

    coordinator.runSchedule(.update) // Prime event buffer
    coordinator.runSchedule(.update)

    #expect(reader.seen == [0])

    coordinator.runSchedule(.update)
    #expect(reader.seen == [0, 1])
}

@Test func drainingEventsConsumesPendingValues() {
    EventEmitterSystem.reset()
    defer { EventEmitterSystem.reset() }
    let coordinator = Coordinator()
    coordinator.update(.update) { schedule in
        schedule.executor = SingleThreadedExecutor()
    }

    let drainer = EventDrainSystem(runAfter: [EventEmitterSystem.id])
    let reader = EventReaderSystem(runAfter: [EventDrainSystem.id])

    coordinator.addSystem(.update, system: EventEmitterSystem())
    coordinator.addSystem(.update, system: drainer)
    coordinator.addSystem(.update, system: reader)

    coordinator.runSchedule(.update) // Prime event buffer
    coordinator.runSchedule(.update)

    #expect(drainer.drained == [[0]])
    #expect(reader.seen.isEmpty)

    coordinator.runSchedule(.update)

    #expect(drainer.drained == [[0], [1]])
    #expect(reader.seen.isEmpty)
}

@Test func drainingEventsSkipsPendingOnCurrentFrame() {
    struct DrainEvent: Sendable, Equatable, Event {
        let id: Int
    }

    let events = EventChannel<DrainEvent>()

    events.send(DrainEvent(id: 1))
    events.prepare()

    events.send(DrainEvent(id: 2))

    let drained = events.drain()
    #expect(drained == [DrainEvent(id: 1)])

    events.prepare()

    var state = EventReaderState<DrainEvent>()
    #expect(events.read(state: &state) == [DrainEvent(id: 2)])
}

@Test func addedQueryFilter() throws {
    struct Tracked: Component, Equatable {
        static let componentTag = ComponentTag.makeTag()
        var value: Int
    }

    final class ManagedMutex<T> {
        let value: Mutex<T>
        init(_ value: sending T) {
            self.value = Mutex(value)
        }
    }

    final class AddedSystem: System {
        static let id = SystemID(name: "AddedSystem")
        nonisolated(unsafe) static let query = Query {
            WithEntityID.self
            Tracked.self
            Added<Tracked>.self
        }

        let captured: ManagedMutex<[Entity.ID]>

        init(captured: ManagedMutex<[Entity.ID]>) {
            self.captured = captured
        }

        var metadata: SystemMetadata {
            Self.metadata(from: [Self.query.schedulingMetadata])
        }

        func run(context: QueryContext, commands: inout Commands) {
            var local: [Entity.ID] = []
            Self.query(context) { entity, _ in
                local.append(entity)
            }
            if !local.isEmpty {
                captured.value.withLock { $0.append(contentsOf: local) }
            }
        }
    }

    let coordinator = Coordinator()
    let captured = ManagedMutex<[Entity.ID]>([])
    coordinator.addSystem(.update, system: AddedSystem(captured: captured))

    let first = coordinator.spawn(Tracked(value: 1))
    coordinator.runSchedule(.update)
    #expect(captured.value.withLock { $0 } == [first])

    captured.value.withLock { $0.removeAll() }
    coordinator.runSchedule(.update)
    #expect(captured.value.withLock { $0 }.isEmpty)

    let second = coordinator.spawn(Tracked(value: 2))
    captured.value.withLock { $0.removeAll() }
    coordinator.runSchedule(.update)
    #expect(captured.value.withLock { $0 } == [second])
}

@Test func changedQueryFilter() throws {
    struct Tracked: Component, Equatable {
        static let componentTag = ComponentTag.makeTag()

        var value: Int
    }

    final class ManagedMutex<T> {
        let value: Mutex<T>
        init(_ value: sending T) {
            self.value = Mutex(value)
        }
    }

    final class ChangedSystem: System {
        static let id = SystemID(name: "ChangedSystem")
        nonisolated(unsafe) static let query = Query {
            WithEntityID.self
            Write<Tracked>.self
            Changed<Tracked>.self
        }

        let captured: ManagedMutex<[Entity.ID]>

        init(captured: ManagedMutex<[Entity.ID]>) {
            self.captured = captured
        }

        var metadata: SystemMetadata {
            Self.metadata(from: [Self.query.schedulingMetadata])
        }

        func run(context: QueryContext, commands: inout Commands) {
            var local: [Entity.ID] = []
            Self.query(context) { entity, _ in
                local.append(entity)
            }
            if !local.isEmpty {
                captured.value.withLock { $0.append(contentsOf: local) }
            }
        }
    }

    let coordinator = Coordinator()
    let captured = ManagedMutex<[Entity.ID]>([])
    coordinator.addSystem(.update, system: ChangedSystem(captured: captured))

    let entity = coordinator.spawn(Tracked(value: 0))
    coordinator.runSchedule(.update)
    #expect(captured.value.withLock { $0 } == [entity])

    captured.value.withLock { $0.removeAll() }
    coordinator.runSchedule(.update)
    #expect(captured.value.withLock { $0 }.isEmpty)

    let mutate = Query { Write<Tracked>.self }
    mutate(coordinator) { (write: Write<Tracked>) in
        write.value += 1
    }

    captured.value.withLock { $0.removeAll() }
    coordinator.runSchedule(.update)
    #expect(captured.value.withLock { $0 } == [entity])
}
