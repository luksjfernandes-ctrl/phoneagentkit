# PhoneAgentKit

Building blocks for a **personal assistant that runs on the iPhone's own model** (Apple Foundation Models) and reads your tools through **MCP**, with your own logins. No server of ours, no API key, no subscription.

This is a framework, not a finished assistant. It does **not** give you an autonomous agent: on-device models this small are not reliable at deciding on their own where to look. What works, measured on a real device, is a narrower pattern, described below.

## Requirements

- iOS 26.4+ or macOS 26.4+ (model variant reporting needs 27)
- A device with Apple Intelligence turned on
- Swift 6.1 toolchain; depends on the official [MCP Swift SDK](https://github.com/modelcontextprotocol/swift-sdk) 0.12.1

## What is inside

| Module | What it does |
|---|---|
| `MCPConnection`, `MCPTool` | Connect to a remote MCP server (streamable HTTP, optional bearer token) and expose each MCP tool to Foundation Models with a schema built at runtime (`DynamicGenerationSchema`). |
| `JSONSchemaConverter` | Converts the subset of JSON Schema that MCP servers use in practice (objects, arrays, enums, scalars). |
| `ToolTrimming`, `ToolBudget` | Shrinks tools to fit the context window: description cut, optional properties dropped, tool output cut, and a greedy fit to a token budget measured by the model itself. |
| `NativeOAuth`, `PKCE` | OAuth 2.1 for native apps: discovery, dynamic client registration (RFC 7591), PKCE S256, and **your app's own URL scheme** as redirect. The official SDK only accepts https/loopback redirects, which does not work on iOS. |
| `TokenStore` | Keeps tokens in the Keychain (this device only). |
| `PinnedSource`, `NumberedMenu`, `LabeledRecord` | The pattern that works: the user points at the source, the code drives, the model fills short forms. |
| `Reader` | Map-reduce reading of long pages that do not fit in the window. |
| `ModelInfo` | Availability, model variant and context size on this device. |

## Numbers we measured (September 2026)

| | iPhone 17 (non-Pro) | Mac M4 |
|---|---|---|
| Model the system gives you | on-device 3B "Core" | "Core Advanced" |
| Context window | **4,096 tokens** | **8,192 tokens** |

The app cannot choose the variant.

- **Raw MCP tools do not fit.** One popular workspace connector exposes 45 tools = **14,221 tokens**; an issue tracker's 38 tools = 8,166 tokens. Trimming is mandatory, not an optimization.
- **Rate limit:** 40 back-to-back calls with the app in the foreground, no throttling. One call once took 127 s.
- **Letting the 3B model find the source by itself:** 13/24 correct. Not reliable.
- **With the source pinned by the user:** 24/30 on one connector, 14/18 on another once fields were labelled by code. The menu choice was right 15/15.

These numbers come from our own test tasks, not a benchmark. Expect different results with other data.

## The pattern that works: pinned source

1. The **user** says where to look (an @mention of a page, project or team).
2. The **code** fetches it. For a database or list, the model only picks a view or filter from a **numbered menu** (`NumberedMenu`).
3. Lists and counts are **rendered by code** from the data, with fields labelled by code (`LabeledRecord`: `Status: Done · Priority: Urgent`). The small model reads structured data as text and mixes fields up (status vs. priority); it also truncates lists.
4. The model writes the final sentence **only from those facts** (`PinnedSource.answer`), which treat the source as data, not instructions.
5. A model choice is ignored when the request does not talk about it (`PinnedSource.gate`): "anything urgent?" does not mean "urgent **and** open".

## What does NOT work (yet)

- **Autonomous search** over a workspace with the 3B model: see the 13/24 above.
- **Apple's Private Cloud Compute** (32K context) from a third-party app requires a managed entitlement. Without it, the app crashes even when availability reports `.available`.
- **The ChatGPT integration in Siri** has no API for third-party apps.
- **Gmail through MCP** requires a Developer Preview and your own Google Cloud project. There is no "connect in one tap" for an open-source app.

## Quick start

```swift
import PhoneAgentKit
import FoundationModels

let client = try await MCPConnection.connect(to: URL(string: "https://mcp.deepwiki.com/mcp")!)
let tools = try await client.listTools().tools
let (kept, _) = try await ToolBudget.fit(tools, client: client, trimming: .init(requiredOnly: true),
                                         budget: ModelInfo.current().contextSize / 2)
let session = LanguageModelSession(tools: kept)
print(try await session.respond(to: "In modelcontextprotocol/swift-sdk, which client transports exist?").content)
```

- **Mac:** `swift run HelloAgentCLI` runs the same example against the public DeepWiki MCP server, with no login.
- **iPhone:** `Examples/HelloAgent` (generate the project with `xcodegen`, pick your signing team).
- **OAuth servers:** create `NativeOAuth(redirectURI: URL(string: "yourapp://oauth/callback")!, clientName: "Your App")`, call `authorize(server:presenter:)` with an `ASWebAuthenticationSession`-backed presenter, then pass the token to `MCPConnection.connect(to:token:)`.

## Tests

`swift test` covers what runs without a device: PKCE (RFC 7636 vector), the authorization URL, the callback state check, form encoding, trimming, the budget fit, schema pruning, menus, labelled records and the gate.

## License

MIT. See [LICENSE](LICENSE).

---

## Resumo em português

O PhoneAgentKit reúne as peças para montar um assistente pessoal que roda no **modelo do próprio iPhone** (Foundation Models, da Apple) e lê as suas ferramentas via **MCP**, com o seu login. Sem servidor nosso, sem chave de API, sem assinatura.

É um framework, **não um agente autônomo**. O que medimos num aparelho real:

- **Janela de contexto:** 4.096 tokens no iPhone não-Pro e 8.192 no Mac M4.
- **Ferramentas cruas estouram a janela:** as 45 de um conector popular somam 14.221 tokens. Enxugar é obrigatório.
- **Busca autônoma no modelo de 3B:** 13/24, não confiável.
- **Com a fonte marcada pelo usuário (@menção):** 24/30 e 14/18. O código conduz, o modelo escolhe num menu numerado, e listas e contagens saem do dado, com campos rotulados pelo código.
- **O que não funciona:**
  - PCC sem o entitlement da Apple: o app cai.
  - ChatGPT da Siri: sem API para apps de terceiros.
  - Gmail: não há conexão de um toque.

Requisitos: iOS 26.4+ (a variante do modelo só aparece no 27) e Apple Intelligence ligado. Licença MIT.
