import ClaudeHarnessAdapter
import Foundation
import SmaltiCore
import Testing

@Suite("Claude project permissions", .serialized)
struct ClaudeProjectPermissionsTests {
    private let project = URL(filePath: NSTemporaryDirectory()).appending(path: "smalti-perm-\(UUID().uuidString)")
    private var settings: URL { project.appending(path: ".claude/settings.local.json") }
    private var path: String { project.path(percentEncoded: false) }

    init() throws {
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
    }

    private func write(_ text: String) throws {
        try FileManager.default.createDirectory(
            at: settings.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: settings)
    }

    private func json() throws -> [String: Any] {
        try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: settings)) as? [String: Any])
    }

    @Test func missingFileReadsEmpty() throws {
        #expect(try ClaudeProjectPermissions().deniedRules(in: path) == [])
    }

    @Test func writesSettingsLocalWithRules() throws {
        try ClaudeProjectPermissions().setDeniedRules(["Read(**/.env)"], in: path)

        #expect((try json()["permissions"] as? [String: Any])?["deny"] as? [String] == ["Read(**/.env)"])
        #expect(try ClaudeProjectPermissions().deniedRules(in: path) == ["Read(**/.env)"])
    }

    @Test func keepsOtherKeys() throws {
        try write(#"{"model":"x","permissions":{"allow":["Bash(ls)"],"deny":["Read(./a)"]}}"#)

        try ClaudeProjectPermissions().setDeniedRules(["Read(./a)", "Read(**/.env)"], in: path)

        let object = try json()
        let permissions = object["permissions"] as? [String: Any]
        #expect(object["model"] as? String == "x")
        #expect(permissions?["allow"] as? [String] == ["Bash(ls)"])
        #expect(permissions?["deny"] as? [String] == ["Read(./a)", "Read(**/.env)"])
    }

    @Test func unreadableSettingsAreLeftUntouched() throws {
        let text = "{\n  // comentario\n  \"model\": \"x\",\n}\n"
        try write(text)

        #expect(throws: ProjectPermissionsError.self) { try ClaudeProjectPermissions().deniedRules(in: path) }
        #expect(throws: ProjectPermissionsError.self) {
            try ClaudeProjectPermissions().setDeniedRules(["Read(**/.env)"], in: path)
        }
        #expect(String(decoding: try Data(contentsOf: settings), as: UTF8.self) == text)
    }

    @Test func nonListDenyIsUnreadable() throws {
        try write(#"{"permissions":{"deny":"Read(./a)"}}"#)

        #expect(throws: ProjectPermissionsError.self) { try ClaudeProjectPermissions().deniedRules(in: path) }
    }

    @Test func unwritableProjectSaysSo() {
        #expect(throws: ProjectPermissionsError.self) {
            try ClaudeProjectPermissions().setDeniedRules(["Read(**/.env)"], in: "/nonexistent-smalti/p")
        }
    }
}
