import Testing
@testable import Components

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
    .iterAll(coordinator)

    func elementTypeIsWriteTransform<S>(_: S) where S: Sequence, S.Element == Write<Transform> {}
    elementTypeIsWriteTransform(transforms)

    #expect(Array(transforms).count == 1_000)

    let multiComponents: LazyWritableQuerySequence<Write<Transform>, Gravity> = Query {
        Write<Transform>.self
        Gravity.self
    }
    .iterAll(coordinator)

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

    let transforms = query.iterAll(coordinator)

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

    // TODO: This will read into random memory, the access buffer isn't valid anymore here:
//    #expect(Array(query.fetchAll(&coordinator)).filter { $0.1.isDownward }.map { $0.0 } == [expectedID] )
}

@Test func queryMetadata() throws {
    let query = Query {
        Write<Transform>.self
        With<Person>.self
        RigidBody.self
        Without<Gravity>.self
    }

    #expect(query.metadata.readSignature == ComponentSignature(RigidBody.componentTag))
    #expect(query.metadata.writeSignature == ComponentSignature(Transform.componentTag))
    #expect(query.metadata.signature == ComponentSignature(Transform.componentTag, Person.componentTag, RigidBody.componentTag))
    #expect(query.metadata.excludedSignature == ComponentSignature(Gravity.componentTag))
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

public struct Gravity: Component {
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

