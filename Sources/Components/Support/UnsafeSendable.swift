//
//  UnsafeSendable.swift
//  Components
//
//  Created by Patrick Horlebein (extern) on 10.10.25.
//

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
