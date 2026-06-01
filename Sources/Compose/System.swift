public protocol System {
    /// A unique ID which identifies this system. Must not change for a given instance.
    var id: SystemID { get }

    /// Metadata of this system.
    /// - Attention: Systems are not allowed to change their metadata once they are scheduled.
    var metadata: SystemMetadata { get }

    func run(context: QueryContext, commands: inout Commands)
}

extension System {
    public static func metadata<each ReadResource, each WriteResource>(
        from queries: [QueryMetadata],
        reading readResources: repeat (each ReadResource).Type,
        writing writeResources: repeat (each WriteResource).Type,
        runAfter: Set<SystemID> = [],
        eventAccess: [(EventKey, SystemMetadata.EventAccess)] = []
    ) -> SystemMetadata {
        var read = ComponentSignature()
        var write = ComponentSignature()
        var exclude = ComponentSignature()

        for query in queries {
            read = read.appending(query.readSignature)
            write = write.appending(query.writeSignature)
            exclude = exclude.appending(query.excludedSignature)
        }

        var access: [(ResourceKey, SystemMetadata.Access)] = []

        for read in repeat each readResources {
            access.append((ResourceKey(read), .read))
        }
        for write in repeat each writeResources {
            access.append((ResourceKey(write), .write))
        }

        return SystemMetadata(
            readSignature: read,
            writeSignature: write,
            excludedSignature: exclude,
            runAfter: runAfter,
            resourceAccess: access,
            eventAccess: eventAccess
        )
    }
}

public struct SystemMetadata {
    public let readSignature: ComponentSignature
    public let writeSignature: ComponentSignature
    public let excludedSignature: ComponentSignature
    public var runAfter: Set<SystemID>

    public let resourceAccess: [(ResourceKey, Access)]
    public let eventAccess: [(EventKey, EventAccess)]

    public enum Access {
        case read
        case write
    }

    public enum EventAccess {
        case read
        case write
        case drain
    }
}

public struct SystemID: Hashable, Sendable {
    public let rawHashValue: Int

    public init(name: String) {
        rawHashValue = name.hashValue
    }
}
