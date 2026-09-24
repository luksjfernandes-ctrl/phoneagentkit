import Foundation
import FoundationModels
import MCP

/// Conexão com um servidor MCP remoto (HTTP streamable), com token opcional no cabeçalho.
public enum MCPConnection {
    public static func connect(to server: URL, token: OAuthToken? = nil,
                               clientName: String = "PhoneAgentKit", version: String = "0.1") async throws -> Client {
        let client = Client(name: clientName, version: version)
        let bearer = token.map { "Bearer " + $0.accessToken }
        let transport = HTTPClientTransport(endpoint: server, streaming: true, requestModifier: { req in
            guard let bearer else { return req }
            var r = req; r.setValue(bearer, forHTTPHeaderField: "Authorization"); return r
        })
        _ = try await client.connect(transport: transport)
        return client
    }

    /// Junta o texto de uma resposta de ferramenta MCP.
    public static func text(_ content: [MCP.Tool.Content]) -> String {
        content.compactMap { if case .text(let t, _, _) = $0 { return t }; return nil }.joined(separator: "\n")
    }
}

/// Uma ferramenta MCP descoberta em tempo de execução, exposta ao Foundation Models com esquema dinâmico.
public struct MCPTool: FoundationModels.Tool {
    public typealias Arguments = GeneratedContent
    public typealias Output = String

    public let name: String
    public let description: String
    public let parameters: GenerationSchema
    let client: Client
    let outputLimit: Int

    public init(_ tool: MCP.Tool, client: Client, trimming: ToolTrimming = .init()) throws {
        name = tool.name
        description = trimming.description(tool.description ?? tool.name)
        outputLimit = trimming.outputLimit
        parameters = try GenerationSchema(
            root: JSONSchemaConverter.convert(tool.inputSchema, name: tool.name + "_args", requiredOnly: trimming.requiredOnly),
            dependencies: [])
        self.client = client
    }

    public func call(arguments: GeneratedContent) async throws -> String {
        let args = try JSONDecoder().decode([String: Value].self, from: Data(arguments.jsonString.utf8))
        let (content, _) = try await client.callTool(name: name, arguments: args)
        // a saída volta para o contexto do modelo: sem corte, uma página sozinha estoura a janela
        return String(MCPConnection.text(content).prefix(outputLimit))
    }
}

/// Converte o subconjunto de JSON Schema que servidores MCP usam na prática.
public enum JSONSchemaConverter {
    /// requiredOnly: descarta propriedades opcionais da raiz (filtros, paginação) para economizar contexto
    public static func convert(_ v: Value, name: String, requiredOnly: Bool = false) -> DynamicGenerationSchema {
        guard case .object(let o) = v else { return DynamicGenerationSchema(type: String.self) }
        let desc = o["description"]?.stringValue
        if case .array(let values)? = o["enum"] {
            return DynamicGenerationSchema(name: name, description: desc, anyOf: values.compactMap(\.stringValue))
        }
        switch o["type"]?.stringValue {
        case "object":
            let required = Set((o["required"]?.arrayValue ?? []).compactMap(\.stringValue))
            var props: [DynamicGenerationSchema.Property] = []
            if case .object(let ps)? = o["properties"] {
                for (k, sub) in ps.sorted(by: { $0.key < $1.key }) where !requiredOnly || required.contains(k) {
                    let subDesc: String? = { if case .object(let so) = sub { return so["description"]?.stringValue }; return nil }()
                    props.append(.init(name: k, description: subDesc, schema: convert(sub, name: name + "_" + k),
                                       isOptional: !required.contains(k)))
                }
            }
            return DynamicGenerationSchema(name: name, description: desc, properties: props)
        case "array":
            return DynamicGenerationSchema(arrayOf: convert(o["items"] ?? .object([:]), name: name + "_item"))
        case "integer": return DynamicGenerationSchema(type: Int.self)
        case "number": return DynamicGenerationSchema(type: Double.self)
        case "boolean": return DynamicGenerationSchema(type: Bool.self)
        default: return DynamicGenerationSchema(type: String.self)
        }
    }

    /// Nomes das propriedades que sobrevivem à conversão (útil para medir o corte).
    public static func propertyNames(_ v: Value, requiredOnly: Bool) -> [String] {
        guard case .object(let o) = v, case .object(let ps)? = o["properties"] else { return [] }
        let required = Set((o["required"]?.arrayValue ?? []).compactMap(\.stringValue))
        return ps.keys.sorted().filter { !requiredOnly || required.contains($0) }
    }
}
