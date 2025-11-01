@usableFromInline
protocol EventChannelBox: AnyObject {
    func prepare()
}

@usableFromInline
final class ConcreteEventChannelBox<E: Event>: EventChannelBox {
    @usableFromInline
    let channel = EventChannel<E>()

    @usableFromInline
    init() {
    }

    @inlinable @inline(__always)
    func prepare() {
        channel.prepare()
    }
}

@usableFromInline
struct EventManager {
    @usableFromInline
    internal var channels: [EventKey: any EventChannelBox] = [:]

    @inlinable @inline(__always)
    mutating func prepare() {
        for channel in channels.values {
            channel.prepare()
        }
    }

    @inlinable @inline(__always)
    mutating func writer<E: Event>(_ type: E.Type = E.self) -> EventWriter<E> {
        EventWriter(channel: channel(for: type))
    }

    @inlinable @inline(__always)
    mutating func send<E: Event>(_ event: E) {
        channel(for: E.self).send(event)
    }

    @inlinable @inline(__always)
    mutating func read<E: Event>(_ type: E.Type = E.self, state: inout EventReaderState<E>) -> EventSequence<E> {
        EventSequence(buffer: channel(for: type).read(state: &state))
    }

    @inlinable @inline(__always)
    mutating func drain<E: Event>(_ type: E.Type = E.self) -> [E] {
        channel(for: type).drain()
    }

    @inlinable @inline(__always)
    mutating func channel<E: Event>(for type: E.Type) -> EventChannel<E> {
        let key = EventKey(type)
        if let existing = channels[key] as? ConcreteEventChannelBox<E> {
            return existing.channel
        }
        let box = ConcreteEventChannelBox<E>()
        channels[key] = box
        return box.channel
    }
}
