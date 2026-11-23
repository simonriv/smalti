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
        let url = FeedbackReport.issueURL(kind: .bug, build: build)

        #expect(url.absoluteString.hasPrefix("https://github.com/simonriv/smalti/issues/new?"))
    }

    @Test(arguments: [(FeedbackKind.bug, "bug"), (.idea, "idea")])
    func issueURLHasTheLabelOfItsKind(_ kind: FeedbackKind, _ label: String) {
        #expect(query(FeedbackReport.issueURL(kind: kind, build: build))["labels"] == label)
    }

    @Test func issueURLHasLabelAndEncodedBody() {
        let url = FeedbackReport.issueURL(kind: .bug, build: build)
        let body = query(url)["body"] ?? ""

        #expect(body.contains("### Qué pasó"))
        #expect(body.contains("### Qué esperabas"))
        #expect(body.contains("### Pasos"))
        #expect(body.contains("Smalti 0.4.5 (abc1234) · macOS 27.2 · Apple M4"))
        #expect(!url.absoluteString.contains(" "))
        #expect(!url.absoluteString.contains("#"))
    }

    @Test func ideaBodyAsksForTheIdea() {
        let body = query(FeedbackReport.issueURL(kind: .idea, build: build))["body"] ?? ""

        #expect(body.contains("### La idea"))
        #expect(body.contains("Smalti 0.4.5"))
    }

    @Test func versionWithAmpersandsAndHashesStaysEncoded() {
        let odd = BuildInfo(version: "0.4.5&x=1#y", commit: "abc", macOS: "27", chip: "M4")

        let body = query(FeedbackReport.issueURL(kind: .bug, build: odd))["body"] ?? ""

        #expect(body.contains("0.4.5&x=1#y"))
    }

    @Test(arguments: [(FeedbackKind.bug, "Fallo: "), (.idea, "Idea: ")])
    func issueTitleStartsWithItsKind(_ kind: FeedbackKind, _ prefix: String) {
        #expect(query(FeedbackReport.issueURL(kind: kind, build: build))["title"] == prefix)
    }

    @Test func issueURLUnder8000Bytes() {
        #expect(FeedbackReport.issueURL(kind: .bug, build: build).absoluteString.utf8.count < 8_000)
    }
}
