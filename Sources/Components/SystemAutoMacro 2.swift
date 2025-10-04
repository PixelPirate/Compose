//import Foundation
//import Swift
//
//// Macro declaration available to the main module even if the implementation target isn't present.
//@attached(member, names: named(id), named(metadata))
//public macro SystemAuto() = SystemAutoMacro
//
//#if canImport(SwiftSyntaxMacros) && canImport(SwiftCompilerPlugin)
//import SwiftDiagnostics
//import SwiftSyntax
//import SwiftSyntaxBuilder
//import SwiftSyntaxMacros
//import SwiftCompilerPlugin
//
//public struct SystemAutoMacro: MemberMacro {
//    public static func expansion(
//        of node: AttributeSyntax,
//        providingMembersOf decl: some DeclGroupSyntax,
//        in context: some MacroExpansionContext
//    ) throws -> [DeclSyntax] {
//        // Determine type name for id synthesis
//        let typeName: String = {
//            if let nominal = decl.as(StructDeclSyntax.self) {
//                return String(nominal.identifier.text)
//            } else if let nominal = decl.as(ClassDeclSyntax.self) {
//                return String(nominal.identifier.text)
//            } else if let nominal = decl.as(ActorDeclSyntax.self) {
//                return String(nominal.identifier.text)
//            } else if let nominal = decl.as(EnumDeclSyntax.self) {
//                return String(nominal.identifier.text)
//            } else {
//                return "System"
//            }
//        }()
//
//        // Gather query property identifiers
//        var queryPropertyNames: [String] = []
//
//        // Gather resource types for reads and writes
//        var readResourceTypes: Set<String> = []
//        var writeResourceTypes: Set<String> = []
//
//        // Fallback: perform a simple textual scan over the declaration source for resource patterns
//        let declSource = String(decl.description)
//
//        // Heuristic 1: find `context.resource(Type.self)` and `context.resource(<T>.self)`
//        do {
//            let pattern = #"\.resource\s*\(\s*([A-Za-z_][A-Za-z0-9_]*)\s*\.self\s*\)"#
//            if let regex = try? Regex(pattern) {
//                for match in declSource.matches(of: regex) {
//                    if let typeNameRange = match.output[1].range {
//                        let t = String(declSource[typeNameRange])
//                        readResourceTypes.insert(t)
//                    }
//                }
//            }
//        }
//
//        // Heuristic 2: find `context[resource: Type.self]` reads and writes
//        // Reads (no assignment): we'll collect all, then subtract those that appear in assignments for write
//        var bracketResourceTypes: [String] = []
//        do {
//            let pattern = #"\[\s*resource\s*:\s*([A-Za-z_][A-Za-z0-9_]*)\s*\.self\s*\]"#
//            if let regex = try? Regex(pattern) {
//                for match in declSource.matches(of: regex) {
//                    if let r = match.output[1].range { bracketResourceTypes.append(String(declSource[r])) }
//                }
//            }
//        }
//        // Writes: look for `context[resource: Type.self] =`
//        do {
//            let pattern = #"\[\s*resource\s*:\s*([A-Za-z_][A-Za-z0-9_]*)\s*\.self\s*\]\s*="#
//            if let regex = try? Regex(pattern) {
//                for match in declSource.matches(of: regex) {
//                    if let r = match.output[1].range { writeResourceTypes.insert(String(declSource[r])) }
//                }
//            }
//        }
//        // Any bracket usages not in writes are reads
//        for t in bracketResourceTypes where !writeResourceTypes.contains(t) {
//            readResourceTypes.insert(t)
//        }
//
//        // Walk members to find query-typed stored properties by type annotation or initializer
//        for member in decl.memberBlock.members {
//            guard let varDecl = member.decl.as(VariableDeclSyntax.self) else { continue }
//            // Only consider stored properties
//            for binding in varDecl.bindings {
//                // Extract identifier
//                guard let pattern = binding.pattern.as(IdentifierPatternSyntax.self) else { continue }
//                let name = String(pattern.identifier.text)
//
//                // Type annotation check
//                var isQuery = false
//                if let typeAnn = binding.typeAnnotation {
//                    let t = typeAnn.type.trimmedDescription
//                    if t.hasPrefix("Query<") || t == "Query" || t.hasPrefix("BuiltQuery<") || t == "BuiltQuery" {
//                        isQuery = true
//                    }
//                }
//                // Initializer check: `= Query(` or `= Query {`
//                if !isQuery, let initValue = binding.initializer?.value {
//                    let text = initValue.trimmedDescription
//                    if text.hasPrefix("Query(") || text.hasPrefix("Query {") || text.hasPrefix("Query<") {
//                        isQuery = true
//                    }
//                }
//                if isQuery { queryPropertyNames.append(name) }
//            }
//        }
//
//        // Build queries array literal elements: `<name>.metadata`
//        let queriesArrayExpr: ExprSyntax = {
//            if queryPropertyNames.isEmpty {
//                return ExprSyntax("[]")
//            } else {
//                let elements = queryPropertyNames.map { "\($0).metadata" }.joined(separator: ", ")
//                return ExprSyntax("[\(raw: "\(elements)")]")
//            }
//        }()
//
//        // Build metadata property body
//        let usesResources = !(readResourceTypes.isEmpty && writeResourceTypes.isEmpty)
//
//        let readTypesList = readResourceTypes.sorted().map { "\($0).self" }.joined(separator: ", ")
//        let writeTypesList = writeResourceTypes.sorted().map { "\($0).self" }.joined(separator: ", ")
//
//        let metadataBody: CodeBlockItemListSyntax = {
//            if usesResources {
//                if !readTypesList.isEmpty && !writeTypesList.isEmpty {
//                    return CodeBlockItemListSyntax("return Self.metadata(from: queries, reading: \(raw: "\(readTypesList)"), writing: \(raw: "\(writeTypesList)"))")
//                } else if !readTypesList.isEmpty {
//                    // No writes: call with reading: and empty writing: using a Void type list trick is invalid; better call from: only and let components capture reads
//                    return CodeBlockItemListSyntax("return Self.metadata(from: queries, reading: \(raw: "\(readTypesList)"), writing: Void.self)")
//                } else {
//                    return CodeBlockItemListSyntax("return Self.metadata(from: queries, reading: Void.self, writing: \(raw: "\(writeTypesList)"))")
//                }
//            } else {
//                return CodeBlockItemListSyntax("return Self.metadata(from: queries)")
//            }
//        }()
//
//        let idDecl: DeclSyntax = "public var id: SystemID { SystemID(name: \"\(raw: typeName)\") }"
//
//        let metadataDecl: DeclSyntax = {
//            let header = "public var metadata: SystemMetadata {"
//            let queriesLet = "let queries: [QueryMetadata] = \(queriesArrayExpr)"
//            let body = metadataBody
//            return DeclSyntax(
//                "\(raw: header)\n    \(raw: queriesLet)\n    \(body)\n}"
//            )
//        }()
//
//        return [idDecl, metadataDecl]
//    }
//}
//
//@main
//struct SystemAutoPlugin: CompilerPlugin {
//    let providingMacros: [Macro.Type] = [
//        SystemAutoMacro.self
//    ]
//}
//
//#endif
