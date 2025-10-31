@usableFromInline
struct UnsafeSendable<T>: @unchecked Sendable {
    @usableFromInline
    let value: T

    @usableFromInline
    init(value: T) {
        self.value = value
    }
}

@usableFromInline
final class UnsafeMutableSendable<T>: @unchecked Sendable {
    @usableFromInline
    var value: T

    @usableFromInline
    init(value: T) {
        self.value = value
    }
}
