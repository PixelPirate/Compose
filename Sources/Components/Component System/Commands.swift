public struct Commands {
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
    public mutating func append(contentsOf sequence: consuming Commands) {
        queue.append(contentsOf: sequence.queue)
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
    public mutating func sendEvent<E: Event>(_ event: E) {
        queue.append(Command(action: { coordinator in
            coordinator.sendEvent(event)
        }))
    }

    @inlinable @inline(__always)
    mutating func integrate(into coordinator: Coordinator) {
        while !queue.isEmpty {
            queue.removeFirst()(coordinator)
        }
    }
}
