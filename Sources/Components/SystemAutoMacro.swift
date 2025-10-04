//import Foundation
//import Swift
//
//@attached(member, names: named(id), named(metadata))
//public macro SystemAuto() = SystemAutoMacro
//
//#if canImport(SwiftSyntaxMacros) && canImport(SwiftCompilerPlugin)
//import SwiftSyntax
//import SwiftSyntaxBuilder
//import SwiftSyntaxMacros
//import SwiftCompilerPlugin
//
//public struct SystemAutoMacro: MemberMacro {
//    public static func expansion(
//        of node: AttributeSyntax,
//        attachedTo declaration: some DeclGroupSyntax,
//        providingMembersOf decl: some DeclGroupSyntax,
//        in context: some MacroExpansionContext
//    ) throws -> [DeclSyntax] {
//        // Find the type name (struct/class/actor)
//        guard let nominalDecl = decl.as(NominalTypeDeclSyntax.self) else {
//            return []
//        }
//        let typeName = nominalDecl.identifier.text
//
//        // Collect property names that are Query or BuiltQuery
//        var queryProperties: [String] = []
//
//        // Collect read and write resource types
//        var readResourceTypes: Set<String> = []
//        var writeResourceTypes: Set<String> = []
//
//        // Helper: extract simple type name string from a TypeSyntax or string representation
//        func typeNameString(from typeSyntax: TypeSyntax) -> String {
//            // For simplicity, get the description trimmed
//            return typeSyntax.description.trimmingCharacters(in: .whitespacesAndNewlines)
//        }
//
//        // Step 1: Scan properties for Query or BuiltQuery types
//        for member in nominalDecl.memberBlock.members {
//            guard let varDecl = member.decl.as(VariableDeclSyntax.self) else { continue }
//            // Only consider stored properties (skip computed properties)
//            // We will consider those with a type annotation starting with Query or BuiltQuery
//            if let binding = varDecl.bindings.first,
//               let typeAnnotation = binding.typeAnnotation {
//                let tname = typeAnnotation.type.description.trimmingCharacters(in: .whitespacesAndNewlines)
//                if tname.hasPrefix("Query") || tname.hasPrefix("BuiltQuery") {
//                    // get variable name(s)
//                    if let pattern = binding.pattern.as(IdentifierPatternSyntax.self) {
//                        queryProperties.append(pattern.identifier.text)
//                    }
//                } else if let initializer = binding.initializer {
//                    // Also check if initialized via Query { ... }
//                    let initStr = initializer.value.description.trimmingCharacters(in: .whitespacesAndNewlines)
//                    if initStr.hasPrefix("Query ") || initStr.hasPrefix("Query{") || initStr.hasPrefix("Query(") {
//                        if let pattern = binding.pattern.as(IdentifierPatternSyntax.self) {
//                            queryProperties.append(pattern.identifier.text)
//                        }
//                    }
//                }
//            }
//        }
//
//        // Step 2: Scan all function bodies and property initializers for resource access
//        func scanResourceAccess(in body: CodeBlockSyntax) {
//            // Simple heuristic: scan all expressions for calls or subscripts like:
//            // context.resource(Type.self) or context.resource()
//            // context[resource: Type.self] (read or write)
//            // We'll do a simple visit on tokens and look for patterns by string description.
//
//            // We'll scan lines for:
//            // - context.resource(Type.self)
//            // - context.resource<Type>()  (not requested, skip)
//            // - context[resource: Type.self] (read or write)
//            // For write detection, we look for assignment to the subscript.
//
//            // Get the text of the body
//            let bodyText = body.description
//
//            // For read:
//            // Match context.resource(Type.self)
//            // Regex-like: context.resource\( *(\w+)\.self *\)
//            // Match context[resource: Type.self]
//            // Regex-like: context\[resource: *(\w+)\.self *\]
//
//            // For write:
//            // context[resource: Type.self] = something
//
//            // Use simple substring search with manual parsing
//
//            func scanPattern(in text: String, pattern: String) -> [String] {
//                var results: [String] = []
//                var searchRange = text.startIndex..<text.endIndex
//
//                while let range = text.range(of: pattern, options: [], range: searchRange) {
//                    let afterPatternIndex = range.upperBound
//                    // After pattern should be (Type.self) or : Type.self]
//
//                    // Attempt to parse Type.self after pattern
//                    // For context.resource(
//                    // pattern = "context.resource("
//                    // For context[resource:
//                    // pattern = "context[resource:"
//
//                    var typeName: String? = nil
//
//                    if afterPatternIndex < text.endIndex {
//                        // parse until first ')' or ']'
//                        let remainder = text[afterPatternIndex...]
//                        if let endIndex = remainder.firstIndex(where: { $0 == ")" || $0 == "]" || $0 == "," || $0.isWhitespace }) {
//                            let typePart = remainder[..<endIndex].trimmingCharacters(in: .whitespaces)
//                            // expect something like Type.self
//                            // remove .self suffix
//                            if typePart.hasSuffix(".self") {
//                                let nameEnd = typePart.index(typePart.endIndex, offsetBy: -5)
//                                let name = String(typePart[..<nameEnd])
//                                if !name.isEmpty {
//                                    typeName = name
//                                }
//                            }
//                        } else {
//                            // no closing char found
//                            // try to read until whitespace or separator
//                            let words = remainder.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
//                            if let first = words.first, first.hasSuffix(".self") {
//                                let nameEnd = first.index(first.endIndex, offsetBy: -5)
//                                let name = String(first[..<nameEnd])
//                                if !name.isEmpty {
//                                    typeName = name
//                                }
//                            }
//                        }
//                    }
//
//                    if let tname = typeName {
//                        results.append(tname)
//                    }
//
//                    searchRange = range.upperBound..<text.endIndex
//                }
//                return results
//            }
//
//            // Read accesses
//            let reads1 = scanPattern(in: bodyText, pattern: "context.resource(")
//            let reads2 = scanPattern(in: bodyText, pattern: "context[resource:")
//            for r in reads1 { readResourceTypes.insert(r) }
//            for r in reads2 { readResourceTypes.insert(r) }
//
//            // Write accesses: look for assignments to context[resource: Type.self] = ...
//            // We'll look for "context[resource: " and then '=' after closing ']'
//
//            var searchRange = bodyText.startIndex..<bodyText.endIndex
//            while let range = bodyText.range(of: "context[resource:", options: [], range: searchRange) {
//                // find closing ']'
//                if let closeBracket = bodyText[range.upperBound...].firstIndex(of: "]") {
//                    let typePart = bodyText[range.upperBound..<closeBracket].trimmingCharacters(in: .whitespaces)
//                    // expect Type.self
//                    var typeName: String? = nil
//                    if typePart.hasSuffix(".self") {
//                        let nameEnd = typePart.index(typePart.endIndex, offsetBy: -5)
//                        let name = String(typePart[..<nameEnd])
//                        if !name.isEmpty {
//                            typeName = name
//                        }
//                    }
//
//                    // check if next non-whitespace after closeBracket is '=' -> write
//                    var afterIndex = closeBracket
//                    while afterIndex < bodyText.endIndex {
//                        afterIndex = bodyText.index(after: afterIndex)
//                        if afterIndex >= bodyText.endIndex { break }
//                        let c = bodyText[afterIndex]
//                        if c.isWhitespace { continue }
//                        else if c == "=" {
//                            if let tn = typeName {
//                                writeResourceTypes.insert(tn)
//                            }
//                        }
//                        break
//                    }
//                    searchRange = closeBracket..<bodyText.endIndex
//                } else {
//                    break
//                }
//            }
//        }
//
//        // Scan member function bodies
//        for member in nominalDecl.memberBlock.members {
//            if let funcDecl = member.decl.as(FunctionDeclSyntax.self),
//               let body = funcDecl.body {
//                scanResourceAccess(in: body)
//            } else if let varDecl = member.decl.as(VariableDeclSyntax.self) {
//                // scan property initializers if present
//                for binding in varDecl.bindings {
//                    if let initializer = binding.initializer,
//                       let expr = initializer.value.as(CodeBlockSyntax.self) {
//                        scanResourceAccess(in: expr)
//                    }
//                }
//            }
//        }
//
//        // Build queriesArraySource string
//        let queriesArraySource: String
//        if queryProperties.isEmpty {
//            queriesArraySource = "[]"
//        } else {
//            let parts = queryProperties.map { "\($0).metadata" }
//            queriesArraySource = "[\(parts.joined(separator: ", "))]"
//        }
//
//        // Build readAppendsSource string
//        let readAppends = readResourceTypes.sorted().map { "access.append((ResourceKey(\($0).self), .read))" }
//        let readAppendsSource = readAppends.joined(separator: "\n        ")
//
//        // Build writeAppendsSource string
//        let writeAppends = writeResourceTypes.sorted().map { "access.append((ResourceKey(\($0).self), .write))" }
//        let writeAppendsSource = writeAppends.joined(separator: "\n        ")
//
//        // Create id declaration
//        let idDecl: DeclSyntax = DeclSyntax("""
//        public var id: SystemID { SystemID(name: "\(typeName)") }
//        """)
//
//        // Create metadata declaration
//        let metadataDeclSource = """
//        public var metadata: SystemMetadata {
//            let queries: [QueryMetadata] = \(queriesArraySource)
//            var include = ComponentSignature()
//            var read = ComponentSignature()
//            var write = ComponentSignature()
//            var exclude = ComponentSignature()
//            for q in queries {
//                include = include.appending(q.signature)
//                read = read.appending(q.readSignature)
//                write = write.appending(q.writeSignature)
//                exclude = exclude.appending(q.excludedSignature)
//            }
//            var access: [(ResourceKey, SystemMetadata.Access)] = []
//            \(readAppendsSource)
//            \(writeAppendsSource)
//            return SystemMetadata(
//                includedSignature: include,
//                readSignature: read,
//                writeSignature: write,
//                excludedSignature: exclude,
//                resourceAccess: access
//            )
//        }
//        """
//        let metadataDecl: DeclSyntax = DeclSyntax(metadataDeclSource)
//
//        return [idDecl, metadataDecl]
//    }
//}
//
//@main
//struct _SystemAutoPlugin: CompilerPlugin {
//    let providingMacros: [Macro.Type] = [
//        SystemAutoMacro.self,
//    ]
//}
//#endif
