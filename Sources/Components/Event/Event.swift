import Foundation

public protocol Event: Sendable { }

public struct EventKey: Hashable, Sendable {
    @usableFromInline
    let type: ObjectIdentifier

    @inlinable @inline(__always)
    public init<E: Event>(_ type: E.Type) {
        self.type = ObjectIdentifier(type)
    }
}

public struct EventReaderState<E: Event>: Sendable {
    @usableFromInline
    internal var lastRead: UInt64

    @inlinable @inline(__always)
    public init() {
        lastRead = 0
    }
}

public struct EventSequence<E: Event>: Sequence {
    @usableFromInline
    internal let buffer: ArraySlice<E>

    @inlinable @inline(__always)
    init(buffer: ArraySlice<E>) {
        self.buffer = buffer
    }

    @inlinable @inline(__always)
    public func makeIterator() -> ArraySlice<E>.Iterator {
        buffer.makeIterator()
    }

    @inlinable @inline(__always)
    public var isEmpty: Bool {
        buffer.isEmpty
    }

    @inlinable @inline(__always)
    public var count: Int {
        buffer.count
    }
}

public struct EventWriter<E: Event> {
    @usableFromInline
    internal let channel: EventChannel<E>

    @inlinable @inline(__always)
    internal init(channel: EventChannel<E>) {
        self.channel = channel
    }

    @inlinable @inline(__always)
    public func send(_ event: E) {
        channel.send(event)
    }

    @inlinable @inline(__always)
    public func send(contentsOf events: some Sequence<E>) {
        for event in events {
            channel.send(event)
        }
    }
}
