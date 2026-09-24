import Foundation
import MCP
import Testing
@testable import PhoneAgentKit

@Suite struct OAuthTests {
    // vetor do apêndice B da RFC 7636
    @Test func pkceChallengeMatchesRFC7636() {
        #expect(PKCE.challenge(for: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk") == "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
    }

    @Test func randomIsURLSafe() {
        let r = PKCE.random(32)
        #expect(!r.contains("+") && !r.contains("/") && !r.contains("="))
        #expect(r.count == 43)
    }

    @Test func authorizationURLCarriesPKCEAndCustomScheme() throws {
        let oauth = NativeOAuth(redirectURI: URL(string: "myapp://oauth/callback")!, clientName: "Example", scope: "read")
        let pkce = PKCE(verifier: "abc")
        let url = oauth.authorizationURL(endpoint: URL(string: "https://auth.example.com/authorize")!, clientID: "cid",
                                         pkce: pkce, state: "s1", resource: "https://mcp.example.com")
        let q = Dictionary(uniqueKeysWithValues: (URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? [])
            .map { ($0.name, $0.value ?? "") })
        #expect(q["redirect_uri"] == "myapp://oauth/callback")
        #expect(q["code_challenge"] == PKCE.challenge(for: "abc"))
        #expect(q["code_challenge_method"] == "S256")
        #expect(q["scope"] == "read")
        #expect(q["state"] == "s1")
    }

    @Test func callbackChecksState() throws {
        let ok = URL(string: "myapp://oauth/callback?code=xyz&state=s1")!
        #expect(try NativeOAuth.code(from: ok, expectedState: "s1") == "xyz")
        #expect(throws: NativeOAuthError.stateMismatch) { try NativeOAuth.code(from: ok, expectedState: "other") }
        let denied = URL(string: "myapp://oauth/callback?error=access_denied&state=s1")!
        #expect(throws: NativeOAuthError.missingCode("access_denied")) { try NativeOAuth.code(from: denied, expectedState: "s1") }
    }

    @Test func formEncodesReservedCharacters() {
        let body = String(data: NativeOAuth.form(["redirect_uri": "myapp://cb?x=1", "code": "a b"]), encoding: .utf8)
        #expect(body == "code=a%20b&redirect_uri=myapp%3A%2F%2Fcb%3Fx%3D1")
    }
}

@Suite struct TrimmingTests {
    @Test func descriptionCutsAtSentenceWhenPossible() {
        let t = ToolTrimming(descriptionLimit: 40)
        #expect(t.description("Short.") == "Short.")
        #expect(t.description("Searches the workspace. Supports many filters and pagination options.") == "Searches the workspace.")
        #expect(t.description(String(repeating: "a", count: 100)).count == 40)
    }

    @Test func budgetKeepsPreferredFirstAndRespectsLimit() async {
        let costs = ["search": 50, "fetch": 40, "admin": 90, "list": 30]
        let (kept, used) = await ToolBudget.fit(Array(costs.keys).sorted(), name: { $0 }, preferred: ["fetch", "search"],
                                                budget: 100) { costs[$0]! }
        #expect(kept == ["fetch", "search"])
        #expect(used == 90)
    }

    @Test func requiredOnlyDropsOptionalProperties() {
        let schema: Value = .object([
            "type": "object",
            "properties": .object(["query": .object(["type": "string"]), "page_size": .object(["type": "integer"])]),
            "required": .array(["query"]),
        ])
        #expect(JSONSchemaConverter.propertyNames(schema, requiredOnly: true) == ["query"])
        #expect(JSONSchemaConverter.propertyNames(schema, requiredOnly: false) == ["page_size", "query"])
    }
}

@Suite struct PinnedSourceTests {
    @Test func menuIsOneBasedAndRejectsOutOfRange() {
        let m = NumberedMenu(["All", "Open", "Done"])
        #expect(m.rendered == "1. All\n2. Open\n3. Done")
        #expect(m.index(for: 2) == 1)
        #expect(m.index(for: 0) == nil)
        #expect(m.index(for: 4) == nil)
    }

    @Test func labeledRecordKeepsFieldsApart() {
        let r = LabeledRecord(id: "ABC-1", title: "Fix login", fields: [("Status", "Done"), ("Priority", "Urgent")])
        #expect(r.line == "ABC-1 — Fix login · Status: Done · Priority: Urgent")
    }

    @Test func listAndCountComeFromData() {
        let rs = [LabeledRecord(id: "A-1", title: "One", fields: [("Status", "Todo")]),
                  LabeledRecord(id: "A-2", title: "Two", fields: [("Status", "Done")])]
        #expect(PinnedSource.renderList(rs, source: "team Example", filter: "priority: High")
                == "2 item(s) in team Example (priority: High):\n- A-1 — One · Status: Todo\n- A-2 — Two · Status: Done")
        #expect(PinnedSource.renderList([], source: "team Example") == "0 item(s) in team Example.")
    }

    @Test func gateIgnoresModelChoiceWhenRequestDoesNotMentionIt() {
        let kw = ["open", "pendente", "status"]
        #expect(PinnedSource.gate(6, default: 0, request: "Anything urgent?", keywords: kw) == 0)
        #expect(PinnedSource.gate(6, default: 0, request: "Quais estão pendentes?", keywords: kw) == 6)
        #expect(PinnedSource.contains("Concluído", "concluido"))
    }
}

@Suite struct ReaderTests {
    @Test func chunksCoverTextUpToMax() {
        let text = String(repeating: "x", count: 5000)
        #expect(Reader.chunks(text, size: 2000).map(\.count) == [2000, 2000, 1000])
        #expect(Reader.chunks(text, size: 100, max: 3).count == 3)
    }
}

@Suite struct MarkdownSectionsTests {
    @Test func splitsByPrefixAndKeepsBodies() {
        let doc = "intro\n# Page: A\n## One\nx\n## Two\ny\n# Page: B\nz"
        let pages = MarkdownSections.split(doc, prefix: "# Page: ")
        #expect(pages.map(\.title) == ["A", "B"])
        #expect(MarkdownSections.split(pages[0].body, prefix: "## ") == [.init(title: "One", body: "x"), .init(title: "Two", body: "y")])
        #expect(pages[1].body == "z")
    }
}

@Suite struct RankTests {
    @Test func titleMatchesComeFirst() {
        let s = [MarkdownSection(title: "Lifecycle", body: "stdio is mentioned once"),
                 MarkdownSection(title: "Transports", body: "stdio stdio"),
                 MarkdownSection(title: "Security", body: "")]
        #expect(MarkdownSections.rank(s, for: "What transports exist for stdio?", limit: 2).map(\.title) == ["Transports", "Lifecycle"])
    }
}

@Suite struct UniqueMatchTests {
    @Test func codeDecidesOnlyWhenOneTitleMatches() {
        let s = [MarkdownSection(title: "Transport Layer", body: ""), MarkdownSection(title: "Security", body: "")]
        #expect(MarkdownSections.uniqueTitleMatch(s, for: "Which transport?") == 0)
        #expect(MarkdownSections.uniqueTitleMatch(s, for: "Tell me everything") == nil)
    }
}
