import Testing
@testable import Compose

// MARK: - Test components

private struct DeltaA: Component, Equatable {
    static let componentTag = ComponentTag.makeTag()
    var value: Int
    init(value: Int = 0) { self.value = value }
}

private struct DeltaB: Component, Equatable {
    static let componentTag = ComponentTag.makeTag()
    var value: Int
    init(value: Int = 0) { self.value = value }
}

// MARK: - Helper box

final class IDBox: @unchecked Sendable { nonisolated(unsafe) var v: [Entity.ID]? }

// MARK: - Structure tests

@Test func diffingQueryForSimpleOutput() {
    let dq = Query { Transform.self }.buildObservationDiffingQuery()
    #expect(dq.requiredTags == [Transform.componentTag])
    #expect(dq.excludedTags == [])
    #expect(dq.outputTags == [Transform.componentTag])
    #expect(dq.optionalTags == [])
    #expect(dq.query.backstageComponents.isEmpty)
    #expect(dq.query.excludedComponents.isEmpty)
    #expect(dq.query.changeFilters.count == 1)
}

@Test func diffingQueryForMultipleOutputs() {
    let dq = Query { Transform.self; Gravity.self }.buildObservationDiffingQuery()
    #expect(dq.requiredTags == [Transform.componentTag, Gravity.componentTag])
    #expect(dq.query.changeFilters.count == 2)
}

@Test func diffingQueryForWithFilter() {
    let dq = Query { Transform.self; With<DeltaA>.self }.buildObservationDiffingQuery()
    #expect(dq.requiredTags == [Transform.componentTag, DeltaA.componentTag])
    #expect(dq.outputTags == [Transform.componentTag])
    #expect(!dq.outputTags.contains(DeltaA.componentTag))
    #expect(dq.query.changeFilters.count == 2)
}

@Test func diffingQueryForWithoutFilter() {
    let dq = Query { Transform.self; Without<DeltaA>.self }.buildObservationDiffingQuery()
    #expect(dq.requiredTags == [Transform.componentTag])
    #expect(dq.excludedTags == [DeltaA.componentTag])
    #expect(dq.query.changeFilters.count == 2)
}

@Test func diffingQueryForOptional() {
    let dq = Query { Transform.self; Optional<DeltaA>.self }.buildObservationDiffingQuery()
    #expect(dq.requiredTags == [Transform.componentTag])
    #expect(dq.outputTags == [Transform.componentTag, DeltaA.componentTag])
    #expect(dq.optionalTags == [DeltaA.componentTag])
    #expect(!dq.requiredTags.contains(DeltaA.componentTag))
}

@Test func diffingQueryHasNoBackstageOrExcluded() {
    let dq = Query { Transform.self; With<DeltaA>.self; Without<DeltaB>.self }.buildObservationDiffingQuery()
    #expect(dq.query.backstageComponents.isEmpty)
    #expect(dq.query.excludedComponents.isEmpty)
}

@Test func diffingQueryNoDuplicateTags() {
    let dq = Query { Transform.self; With<Transform>.self }.buildObservationDiffingQuery()
    #expect(dq.requiredTags == [Transform.componentTag])
    #expect(dq.query.changeFilters.count == 1)
}

// MARK: - Behavioral tests (single system, prime then verify)

@Test func diffingQueryDetectsAddedComponent() {
    let coordinator = Coordinator()
    _ = coordinator.spawn(Transform(position: Vector3(x: 1, y: 0, z: 0), rotation: .zero, scale: .zero))

    let dq = Query { Transform.self }.buildObservationDiffingQuery()
    let box = IDBox()
    struct S: System {
        let id = SystemID(name: "DS")
        let q: Query<WithEntityID>
        let box: IDBox
        var metadata: SystemMetadata { Self.metadata(from: [q.schedulingMetadata]) }
        func run(context: QueryContext, commands: inout Commands) { box.v = Array(q.fetchAll(context)) }
    }
    coordinator.addSystem(S(q: dq.query, box: box), schedule: .perceptionObservation)

    coordinator.runSchedule(.perceptionObservation) // prime
    _ = coordinator.spawn(Transform(position: Vector3(x: 2, y: 0, z: 0), rotation: .zero, scale: .zero))
    coordinator.runSchedule(.perceptionObservation) // verify

    #expect(box.v?.count == 1)
}

@Test func diffingQueryDetectsChangedComponent() {
    let coordinator = Coordinator()
    let e1 = coordinator.spawn(Transform(position: Vector3(x: 1, y: 0, z: 0), rotation: .zero, scale: .zero))

    let dq = Query { Transform.self }.buildObservationDiffingQuery()
    let box = IDBox()
    struct S: System {
        let id = SystemID(name: "DS")
        let q: Query<WithEntityID>
        let box: IDBox
        var metadata: SystemMetadata { Self.metadata(from: [q.schedulingMetadata]) }
        func run(context: QueryContext, commands: inout Commands) { box.v = Array(q.fetchAll(context)) }
    }
    coordinator.addSystem(S(q: dq.query, box: box), schedule: .perceptionObservation)

    coordinator.runSchedule(.perceptionObservation)
    coordinator.remove(Transform.self, from: e1)
    coordinator.add(Transform(position: Vector3(x: 99, y: 0, z: 0), rotation: .zero, scale: .zero), to: e1)
    coordinator.runSchedule(.perceptionObservation)

    #expect(box.v?.count == 1)
}

@Test func diffingQueryDetectsRemovedComponent() {
    let coordinator = Coordinator()
    let e1 = coordinator.spawn(Transform(position: .zero, rotation: .zero, scale: .zero))

    let dq = Query { Transform.self }.buildObservationDiffingQuery()
    let box = IDBox()
    struct S: System {
        let id = SystemID(name: "DS")
        let q: Query<WithEntityID>
        let box: IDBox
        var metadata: SystemMetadata { Self.metadata(from: [q.schedulingMetadata]) }
        func run(context: QueryContext, commands: inout Commands) { box.v = Array(q.fetchAll(context)) }
    }
    coordinator.addSystem(S(q: dq.query, box: box), schedule: .perceptionObservation)

    coordinator.runSchedule(.perceptionObservation)
    coordinator.remove(Transform.self, from: e1)
    coordinator.runSchedule(.perceptionObservation)

    #expect(box.v?.count == 1)
    #expect(box.v?[0] == e1)
}

@Test func diffingQueryDetectsWithFilterAddition() {
    let coordinator = Coordinator()
    _ = coordinator.spawn(Transform(position: .zero, rotation: .zero, scale: .zero))
    let e1 = coordinator.spawn(Transform(position: Vector3(x: 1, y: 0, z: 0), rotation: .zero, scale: .zero))

    let dq = Query { Transform.self; With<DeltaA>.self }.buildObservationDiffingQuery()
    let box = IDBox()
    struct S: System {
        let id = SystemID(name: "DS")
        let q: Query<WithEntityID>
        let box: IDBox
        var metadata: SystemMetadata { Self.metadata(from: [q.schedulingMetadata]) }
        func run(context: QueryContext, commands: inout Commands) { box.v = Array(q.fetchAll(context)) }
    }
    coordinator.addSystem(S(q: dq.query, box: box), schedule: .perceptionObservation)

    coordinator.runSchedule(.perceptionObservation)
    coordinator.add(DeltaA(value: 99), to: e1)
    coordinator.runSchedule(.perceptionObservation)

    #expect(box.v?.count == 1)
    #expect(box.v?[0] == e1)
}

@Test func diffingQueryDetectsWithFilterRemoval() {
    let coordinator = Coordinator()
    let e1 = coordinator.spawn(
        Transform(position: .zero, rotation: .zero, scale: .zero),
        DeltaA(value: 42)
    )

    let dq = Query { Transform.self; With<DeltaA>.self }.buildObservationDiffingQuery()
    let box = IDBox()
    struct S: System {
        let id = SystemID(name: "DS")
        let q: Query<WithEntityID>
        let box: IDBox
        var metadata: SystemMetadata { Self.metadata(from: [q.schedulingMetadata]) }
        func run(context: QueryContext, commands: inout Commands) { box.v = Array(q.fetchAll(context)) }
    }
    coordinator.addSystem(S(q: dq.query, box: box), schedule: .perceptionObservation)

    coordinator.runSchedule(.perceptionObservation)
    coordinator.remove(DeltaA.self, from: e1)
    coordinator.runSchedule(.perceptionObservation)

    #expect(box.v?.count == 1)
    #expect(box.v?[0] == e1)
}

@Test func diffingQueryDetectsWithoutFilterAddition() {
    let coordinator = Coordinator()
    let e1 = coordinator.spawn(Transform(position: .zero, rotation: .zero, scale: .zero))

    let dq = Query { Transform.self; Without<DeltaA>.self }.buildObservationDiffingQuery()
    let box = IDBox()
    struct S: System {
        let id = SystemID(name: "DS")
        let q: Query<WithEntityID>
        let box: IDBox
        var metadata: SystemMetadata { Self.metadata(from: [q.schedulingMetadata]) }
        func run(context: QueryContext, commands: inout Commands) { box.v = Array(q.fetchAll(context)) }
    }
    coordinator.addSystem(S(q: dq.query, box: box), schedule: .perceptionObservation)

    coordinator.runSchedule(.perceptionObservation)
    coordinator.add(DeltaA(value: 1), to: e1)
    coordinator.runSchedule(.perceptionObservation)

    #expect(box.v?.count == 1)
    #expect(box.v?[0] == e1)
}

@Test func diffingQueryDetectsWithoutFilterRemoval() {
    let coordinator = Coordinator()
    let e1 = coordinator.spawn(
        Transform(position: .zero, rotation: .zero, scale: .zero),
        DeltaA(value: 1)
    )

    let dq = Query { Transform.self; Without<DeltaA>.self }.buildObservationDiffingQuery()
    let box = IDBox()
    struct S: System {
        let id = SystemID(name: "DS")
        let q: Query<WithEntityID>
        let box: IDBox
        var metadata: SystemMetadata { Self.metadata(from: [q.schedulingMetadata]) }
        func run(context: QueryContext, commands: inout Commands) { box.v = Array(q.fetchAll(context)) }
    }
    coordinator.addSystem(S(q: dq.query, box: box), schedule: .perceptionObservation)

    coordinator.runSchedule(.perceptionObservation)
    coordinator.remove(DeltaA.self, from: e1)
    coordinator.runSchedule(.perceptionObservation)

    #expect(box.v?.count == 1)
    #expect(box.v?[0] == e1)
}

@Test func diffingQueryDetectsOptionalAdded() {
    let coordinator = Coordinator()
    _ = coordinator.spawn(Transform(position: .zero, rotation: .zero, scale: .zero))
    let e1 = coordinator.spawn(Transform(position: Vector3(x: 1, y: 0, z: 0), rotation: .zero, scale: .zero))

    let dq = Query { Transform.self; Optional<DeltaA>.self }.buildObservationDiffingQuery()
    let box = IDBox()
    struct S: System {
        let id = SystemID(name: "DS")
        let q: Query<WithEntityID>
        let box: IDBox
        var metadata: SystemMetadata { Self.metadata(from: [q.schedulingMetadata]) }
        func run(context: QueryContext, commands: inout Commands) { box.v = Array(q.fetchAll(context)) }
    }
    coordinator.addSystem(S(q: dq.query, box: box), schedule: .perceptionObservation)

    coordinator.runSchedule(.perceptionObservation)
    coordinator.add(DeltaA(value: 99), to: e1)
    coordinator.runSchedule(.perceptionObservation)

    #expect(box.v?.count == 1)
}

@Test func diffingQueryDetectsOptionalRemoved() {
    let coordinator = Coordinator()
    let e1 = coordinator.spawn(
        Transform(position: .zero, rotation: .zero, scale: .zero),
        DeltaA(value: 1)
    )

    let dq = Query { Transform.self; Optional<DeltaA>.self }.buildObservationDiffingQuery()
    let box = IDBox()
    struct S: System {
        let id = SystemID(name: "DS")
        let q: Query<WithEntityID>
        let box: IDBox
        var metadata: SystemMetadata { Self.metadata(from: [q.schedulingMetadata]) }
        func run(context: QueryContext, commands: inout Commands) { box.v = Array(q.fetchAll(context)) }
    }
    coordinator.addSystem(S(q: dq.query, box: box), schedule: .perceptionObservation)

    coordinator.runSchedule(.perceptionObservation)
    coordinator.remove(DeltaA.self, from: e1)
    coordinator.runSchedule(.perceptionObservation)

    #expect(box.v?.count == 1)
    #expect(box.v?[0] == e1)
}

@Test func diffingQueryDetectsOptionalChanged() {
    let coordinator = Coordinator()
    let e1 = coordinator.spawn(
        Transform(position: .zero, rotation: .zero, scale: .zero),
        DeltaA(value: 1)
    )

    let dq = Query { Transform.self; Optional<DeltaA>.self }.buildObservationDiffingQuery()
    let box = IDBox()
    struct S: System {
        let id = SystemID(name: "DS")
        let q: Query<WithEntityID>
        let box: IDBox
        var metadata: SystemMetadata { Self.metadata(from: [q.schedulingMetadata]) }
        func run(context: QueryContext, commands: inout Commands) { box.v = Array(q.fetchAll(context)) }
    }
    coordinator.addSystem(S(q: dq.query, box: box), schedule: .perceptionObservation)

    coordinator.runSchedule(.perceptionObservation)
    coordinator.remove(DeltaA.self, from: e1)
    coordinator.add(DeltaA(value: 42), to: e1)
    coordinator.runSchedule(.perceptionObservation)

    #expect(box.v?.count == 1)
}

@Test func diffingQueryDetectsMultipleChangesInOneTick() {
    let coordinator = Coordinator()
    let e1 = coordinator.spawn(
        Transform(position: Vector3(x: 1, y: 0, z: 0), rotation: .zero, scale: .zero),
        Gravity(force: Vector3(x: 9.8, y: 0, z: 0))
    )

    let dq = Query { Transform.self; Gravity.self }.buildObservationDiffingQuery()
    let box = IDBox()
    struct S: System {
        let id = SystemID(name: "DS")
        let q: Query<WithEntityID>
        let box: IDBox
        var metadata: SystemMetadata { Self.metadata(from: [q.schedulingMetadata]) }
        func run(context: QueryContext, commands: inout Commands) { box.v = Array(q.fetchAll(context)) }
    }
    coordinator.addSystem(S(q: dq.query, box: box), schedule: .perceptionObservation)

    coordinator.runSchedule(.perceptionObservation)
    coordinator.remove(Transform.self, from: e1)
    coordinator.add(Transform(position: Vector3(x: 42, y: 0, z: 0), rotation: .zero, scale: .zero), to: e1)
    coordinator.remove(Gravity.self, from: e1)
    coordinator.add(Gravity(force: Vector3(x: 3.14, y: 0, z: 0)), to: e1)
    coordinator.runSchedule(.perceptionObservation)

    #expect(box.v?.count == 1)
    #expect(box.v?[0] == e1)
}

@Test func unchangedEntitiesAreNotReturned() {
    let coordinator = Coordinator()
    _ = coordinator.spawn(Transform(position: Vector3(x: 1, y: 0, z: 0), rotation: .zero, scale: .zero))

    let dq = Query { Transform.self }.buildObservationDiffingQuery()
    let box = IDBox()
    struct S: System {
        let id = SystemID(name: "DS")
        let q: Query<WithEntityID>
        let box: IDBox
        var metadata: SystemMetadata { Self.metadata(from: [q.schedulingMetadata]) }
        func run(context: QueryContext, commands: inout Commands) { box.v = Array(q.fetchAll(context)) }
    }
    coordinator.addSystem(S(q: dq.query, box: box), schedule: .perceptionObservation)

    coordinator.runSchedule(.perceptionObservation) // prime
    coordinator.runSchedule(.perceptionObservation) // no changes

    #expect(box.v?.isEmpty == true)
}
