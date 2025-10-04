public protocol System {
    var id: SystemID { get }
    var metadata: SystemMetadata { get }

    func run(context: QueryContext, commands: inout Commands)
}

extension System {
    public static func metadata<each ReadResource, each WriteResource>(
        from queries: [QueryMetadata],
        reading readResources: repeat (each ReadResource).Type,
        writing writeResources: repeat (each WriteResource).Type
    ) -> SystemMetadata {
        var include = ComponentSignature()
        var read = ComponentSignature()
        var write = ComponentSignature()
        var exclude = ComponentSignature()

        for query in queries {
            include = include.appending(query.signature)
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
            includedSignature: include,
            readSignature: read,
            writeSignature: write,
            excludedSignature: exclude,
            resourceAccess: access
        )
    }

//    public static func metadata(
//        from queries: [QueryMetadata]
//    ) -> SystemMetadata {
//        var include = ComponentSignature()
//        var read = ComponentSignature()
//        var write = ComponentSignature()
//        var exclude = ComponentSignature()
//
//        for query in queries {
//            include = include.appending(query.signature)
//            read = read.appending(query.readSignature)
//            write = write.appending(query.writeSignature)
//            exclude = exclude.appending(query.excludedSignature)
//        }
//
//        return SystemMetadata(
//            includedSignature: include,
//            readSignature: read,
//            writeSignature: write,
//            excludedSignature: exclude,
//            resourceAccess: []
//        )
//    }
}

public struct SystemMetadata {
    public let includedSignature: ComponentSignature
    public let readSignature: ComponentSignature
    public let writeSignature: ComponentSignature
    public let excludedSignature: ComponentSignature

    public let resourceAccess: [(ResourceKey, Access)]

    public enum Access {
        case read
        case write
    }
}

public struct SystemID: Hashable {
    public let rawHashValue: Int

    public init(name: String) {
        rawHashValue = name.hashValue
    }
}
