import Foundation
import SmaltiCore
import SmaltiCoreTestSupport
import Testing

import TOMLConfigAdapter

@MainActor
@Suite("TOMLConfigStore")
struct TOMLConfigStoreContractTests {
    @Test func missingFileGivesDefaults() throws {
        let store = TOMLConfigStore(file: Fixture.url("does-not-exist"))

        let reloaded = try store.reload()

        #expect(reloaded == .defaults)
        #expect(store.current() == .defaults)
    }

    @Test func reloadReadsTheFile() throws {
        let store = TOMLConfigStore(file: Fixture.url("custom-shell"))

        let reloaded = try store.reload()

        #expect(reloaded.shell == .custom("/bin/zsh -f"))
        #expect(store.current() == reloaded)
    }

    @Test func errorNamesTheFile() {
        let file = Fixture.url("syntax-error")
        let store = TOMLConfigStore(file: file)

        #expect(
            throws: ConfigError(
                file: file.path(percentEncoded: false), line: 3, key: nil, reason: "sintaxis TOML no válida")
        ) {
            try store.reload()
        }
    }

    @Test func fileThatIsNotUTF8IsReportedAsSuch() throws {
        let harness = try TemporaryFileHarness()
        defer { harness.removeDirectory() }
        let file = try harness.writeBytes([0x5B, 0x6B, 0x65, 0x79, 0x73, 0x5D, 0x0A, 0xFF, 0xFE, 0xFD])
        let store = TOMLConfigStore(file: file)

        #expect(
            throws: ConfigError(
                file: file.path(percentEncoded: false), line: nil, key: nil, reason: "el archivo no está en UTF-8")
        ) {
            try store.reload()
        }
    }

    @Test func fileWithoutReadPermissionIsReportedAsSuch() throws {
        let harness = try TemporaryFileHarness()
        defer { harness.removeDirectory() }
        let file = try harness.writeBytes(Array("[keys]\n".utf8))
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o000], ofItemAtPath: file.path(percentEncoded: false))
        let store = TOMLConfigStore(file: file)

        #expect(
            throws: ConfigError(
                file: file.path(percentEncoded: false), line: nil, key: nil,
                reason: "no se pudo leer el archivo: sin permiso de lectura")
        ) {
            try store.reload()
        }
    }

    @Test func tomlStoreSatisfiesContract() throws {
        let harness = try TemporaryFileHarness()
        defer { harness.removeDirectory() }

        try ConfigStoreContract.verify(harness)
    }
}

/// Writes each scenario to `config.toml` in a fresh temporary directory.
@MainActor
private final class TemporaryFileHarness: ConfigStoreHarness {
    private let directory: URL
    private var file: URL { directory.appending(path: "config.toml") }

    init() throws {
        directory = FileManager.default.temporaryDirectory.appending(path: "smalti-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    func makeStore() -> any ConfigStore {
        TOMLConfigStore(file: file)
    }

    func write(_ scenario: ConfigScenario) {
        do {
            try apply(scenario)
        } catch {
            Issue.record(error, "Could not write scenario \(scenario)")
        }
    }

    func removeDirectory() {
        do {
            try FileManager.default.removeItem(at: directory)
        } catch {
            Issue.record(error, "Could not remove \(directory.path(percentEncoded: false))")
        }
    }

    /// Writes raw bytes to the store's file and returns its URL.
    func writeBytes(_ bytes: [UInt8]) throws -> URL {
        try Data(bytes).write(to: file)
        return file
    }

    private func apply(_ scenario: ConfigScenario) throws {
        switch scenario {
        case .missing:
            if FileManager.default.fileExists(atPath: file.path(percentEncoded: false)) {
                try FileManager.default.removeItem(at: file)
            }
        case .customShellAndColumns:
            try write("[tiling]\ndefault_layout = \"columns\"\n\n[shell]\ncommand = \"/bin/zsh -f\"\n")
        case .invalid:
            try write("[appearance]\nfont_size = \"trece\"\n")
        }
    }

    private func write(_ text: String) throws {
        try text.write(to: file, atomically: true, encoding: .utf8)
    }
}
