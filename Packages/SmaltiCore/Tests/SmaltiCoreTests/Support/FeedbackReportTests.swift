import Foundation
import SmaltiCore
import Testing

@Suite("FeedbackReport")
struct FeedbackReportTests {
    private let build = BuildInfo(version: "0.4.5", commit: "abc1234", macOS: "27.2", chip: "Apple M4")

    private func query(_ url: URL) -> [String: String] {
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        return Dictionary(items.map { ($0.name, $0.value ?? "") }) { first, _ in first }
    }

    @Test func summaryFormat() {
        #expect(build.summary == "Smalti 0.4.5 (abc1234) · macOS 27.2 · Apple M4")
    }

    @Test func issueURLPointsAtTheRepository() {
        let url = FeedbackReport.issueURL(kind: .bug, build: build, texts: .spanish)

        #expect(url.absoluteString.hasPrefix("https://github.com/simonriv/smalti/issues/new?"))
    }

    /// F7.6: the public repo's issue forms; the form adds its own label.
    @Test(arguments: [(FeedbackKind.bug, "bug.yml"), (.idea, "idea.yml")])
    func issueURLOpensTheFormOfItsKind(_ kind: FeedbackKind, _ template: String) {
        #expect(query(FeedbackReport.issueURL(kind: kind, build: build, texts: .spanish))["template"] == template)
    }

    @Test(arguments: [FeedbackKind.bug, .idea])
    func issueURLFillsTheBuildField(_ kind: FeedbackKind) {
        #expect(query(FeedbackReport.issueURL(kind: kind, build: build, texts: .spanish))["build"] == build.summary)
    }

    @Test func issueURLLeavesLabelsAndBodyToTheForm() {
        let names = Set(query(FeedbackReport.issueURL(kind: .bug, build: build, texts: .spanish)).keys)

        #expect(names == ["template", "title", "build"])
    }

    @Test func formFieldIDsAreStable() {
        #expect(FeedbackReport.buildFieldID == "build")
    }

    @Test func versionWithAmpersandsAndHashesStaysEncoded() {
        let odd = BuildInfo(version: "0.4.5&x=1#y", commit: "abc", macOS: "27", chip: "M4")

        let url = FeedbackReport.issueURL(kind: .bug, build: odd, texts: .spanish)

        #expect(query(url)["build"]?.contains("0.4.5&x=1#y") == true)
        #expect(!url.absoluteString.contains(" "))
        #expect(!url.absoluteString.dropFirst(8).contains("#"))
    }

    @Test(arguments: [(FeedbackKind.bug, "Fallo: "), (.idea, "Idea: ")])
    func issueTitleStartsWithItsKind(_ kind: FeedbackKind, _ prefix: String) {
        #expect(query(FeedbackReport.issueURL(kind: kind, build: build, texts: .spanish))["title"] == prefix)
    }

    @Test func issueURLUnder8000Bytes() {
        #expect(FeedbackReport.issueURL(kind: .bug, build: build, texts: .spanish).absoluteString.utf8.count < 8_000)
    }
}
