import Testing
import Components

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

        let duration = clock.measure {
            query(coordinator) { transform, gravity in
                transform.position.x += gravity.force.x
            }
        }
    //~0.012 seconds (Iteration)
    //~0.014 seconds (Signature)
        print(duration)
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
            query(coordinator) { com1, com2, com3 in
                com1.numberWang = com2.numberWang * com3.numberWang * com2.numberWang
            }
        }

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
            let transforms = query.iterAll(coordinator)

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

