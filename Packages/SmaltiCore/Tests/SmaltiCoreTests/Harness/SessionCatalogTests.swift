import Foundation
import SmaltiCore
import Testing

@Suite("Session catalog")
struct SessionCatalogTests {
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    private func session(_ id: String, _ harness: HarnessID, updated seconds: TimeInterval, title: String = "t")
        -> HarnessSession
    {
        HarnessSession(
            harness: harness, id: id, directory: "/w/\(id)", title: title, createdAt: t0,
            updatedAt: t0.addingTimeInterval(seconds), detail: nil)
    }

    @Test func mergesNewestFirstAcrossHarnesses() {
        let listing = SessionCatalog.merge(
            [.success([session("a", .codex, updated: 10)]), .success([session("b", .opencode, updated: 20)])],
            query: SessionQuery())

        #expect(listing.sessions.map(\.id) == ["b", "a"])
    }

    @Test func failingAdapterKeepsOthers() {
        let failure = HarnessError.storeMissing(harness: .antigravity, path: "/x")

        let listing = SessionCatalog.merge(
            [.failure(failure), .success([session("a", .codex, updated: 1)])], query: SessionQuery())

        #expect(listing.sessions.map(\.id) == ["a"])
        #expect(listing.failures == [.antigravity: failure])
    }

    @Test func capsAtLimit() {
        let many = (0..<201).map { session("s\($0)", .codex, updated: TimeInterval($0)) }

        let listing = SessionCatalog.merge([.success(many)], query: SessionQuery())

        #expect(listing.sessions.count == 200)
        #expect(listing.sessions.first?.id == "s200")
    }

    @Test func filtersByHarnessAndText() {
        let lists: [Result<[HarnessSession], HarnessError>] = [
            .success([session("a", .codex, updated: 1, title: "Migración RLS"), session("b", .codex, updated: 2)]),
            .success([session("c", .opencode, updated: 3, title: "Migración landing")]),
        ]

        let listing = SessionCatalog.merge(lists, query: SessionQuery(harness: .codex, text: "migra"))

        #expect(listing.sessions.map(\.id) == ["a"])
    }

    @Test func emptyListsGiveEmptyListing() {
        let listing = SessionCatalog.merge([], query: SessionQuery())

        #expect(listing.sessions.isEmpty)
        #expect(listing.failures.isEmpty)
    }

    @Test func errorMessageNamesHarnessAndReason() {
        let error = HarnessError.unknownSchema(harness: .codex, path: "/c/state_5.sqlite", missing: "cwd")

        #expect(error.message == "No se pudo leer Codex: esquema desconocido (falta cwd)")
    }
}

@Suite("Session query")
struct SessionQueryTests {
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func textMatchesTitleOrProject() {
        let session = HarnessSession(
            harness: .codex, id: "x", directory: "/Users/s/dev/solen", title: "Agendar recordatorios",
            createdAt: t0, updatedAt: t0, detail: nil)

        #expect(SessionQuery(text: "solen").matches(session))
        #expect(SessionQuery(text: "agendar").matches(session))
        #expect(!SessionQuery(text: "rizaria").matches(session))
    }

    @Test func directoryFilterComparesResolvedPaths() {
        let session = HarnessSession(
            harness: .codex, id: "x", directory: "/private/tmp/w", title: "t", createdAt: t0, updatedAt: t0,
            detail: nil)

        #expect(SessionQuery(directory: "/tmp/w/").matches(session))
        #expect(!SessionQuery(directory: "/tmp/other").matches(session))
    }

    @Test func directoriesCompareResolved() {
        #expect(ResolvedPath.same("/private/tmp/x/", "/tmp/x"))
        #expect(ResolvedPath.same("/private/var/folders/a", "/var/folders/a"))
        #expect(!ResolvedPath.same("/tmp/x", "/tmp/xy"))
        #expect(!ResolvedPath.same("/private/etc", "/etc/x"))
    }
}

@Suite("Shell word")
struct ShellWordTests {
    @Test func quotesHostileText() {
        #expect(ShellWord.quoted("a'b") == #"'a'\''b'"#)
        #expect(ShellWord.quoted("01a210a3-2dac_x") == "01a210a3-2dac_x")
        #expect(ShellWord.quoted("") == "''")
        #expect(ShellWord.quoted("a b$c") == "'a b$c'")
    }
}
