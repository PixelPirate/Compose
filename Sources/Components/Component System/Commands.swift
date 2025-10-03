public struct Commands: ~Copyable {
    public struct Command {
        @usableFromInline
        let action: (Coordinator) -> Void

        @inlinable @inline(__always)
        public init(action: @escaping (Coordinator) -> Void) {
            self.action = action
        }

        @usableFromInline
        func callAsFunction(_ coordinator: Coordinator) {
            action(coordinator)
        }
    }

    @usableFromInline
    internal var queue: [Command] = []

    @inlinable @inline(__always)
    public init(queue: [Command] = []) {
        self.queue = queue
    }

    @inlinable @inline(__always)
    public mutating func add<C: Component>(component: C, to entityID: Entity.ID) {
        queue.append(Command(action: { coordinator in
            coordinator.add(component, to: entityID)
        }))
    }

    @inlinable @inline(__always)
    public mutating func remove<C: Component>(component: C.Type, from entityID: Entity.ID) {
        queue.append(Command(action: { coordinator in
            coordinator.remove(C.componentTag, from: entityID)
        }))
    }

    @inlinable @inline(__always)
    public mutating func spawn<each C: Component>(component: repeat each C, then: @escaping (Coordinator, Entity.ID) -> Void) {
        queue.append(Command(action: { coordinator in
            let entityID = coordinator.spawn(repeat each component)
            then(coordinator, entityID)
        }))
    }

    @inlinable @inline(__always)
    public mutating func spawn(then: @escaping (Coordinator, Entity.ID) -> Void) {
        queue.append(Command(action: { coordinator in
            let entityID = coordinator.spawn()
            then(coordinator, entityID)
        }))
    }

    @inlinable @inline(__always)
    public mutating func destroy(_ entity: Entity.ID) {
        queue.append(Command(action: { coordinator in
            coordinator.destroy(entity)
        }))
    }

    @inlinable @inline(__always)
    public mutating func run(_ action: @escaping (Coordinator) -> Void) {
        queue.append(Command(action: { coordinator in
            action(coordinator)
        }))
    }

    @inlinable @inline(__always)
    mutating func integrate(into coordinator: Coordinator) {
        while let command = queue.popLast() {
            command(coordinator)
        }
    }
}
