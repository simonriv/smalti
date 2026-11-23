import Foundation
import SmaltiCore

/// The app's state on disk (`~/Library/Application Support/<build>/`):
///
/// ```text
/// session.json                 snapshot (readable JSON, with a format version)
/// scrollback/<uuid>.lzfse      scrollback per pane, LZFSE
/// history/<uuid>.zsh_history   history per pane (written by zsh; only pruned here)
/// layouts/<name>.json          named layouts
/// preferences.json             { "restore": "ask" | "always" } until F5
/// ```
///
/// The directory is owner-only (0700). A snapshot that cannot be read is renamed to `session.corrupt-<date>.json`
/// and reported, never blocking the launch.
@MainActor
public final class FileSessionArchive: SessionArchive, PaneTranscripts, NamedLayouts, RestorePreferenceStore {
    private let directory: URL
    private let files: PaneFileLocator
    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()
    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    public init(directory: URL) {
        self.directory = directory
        files = PaneFileLocator(stateDirectory: directory)
    }

    private var sessionFile: URL { directory.appending(path: "session.json") }
    private var preferencesFile: URL { directory.appending(path: "preferences.json") }
    private var scrollbackDirectory: URL { directory.appending(path: "scrollback") }
    private var layoutsDirectory: URL { directory.appending(path: "layouts") }

    // MARK: SessionArchive

    public func save(_ snapshot: SessionSnapshot) throws(SessionArchiveError) {
        try write(encoded(snapshot, file: sessionFile), to: sessionFile)
    }

    public func lastSession() -> LastSession {
        guard let data = try? Data(contentsOf: sessionFile) else { return .none }
        do {
            let snapshot = try decoder.decode(SessionSnapshot.self, from: data)
            guard snapshot.version == SessionSnapshot.formatVersion else {
                return setAside(reason: "unknown format version \(snapshot.version)")
            }
            return .saved(snapshot)
        } catch {
            return setAside(reason: "session.json: \(error)")
        }
    }

    private func setAside(reason: String) -> LastSession {
        let stamp = ISO8601DateFormatter.string(
            from: .now, timeZone: .gmt, formatOptions: [.withYear, .withMonth, .withDay, .withTime])
        let aside = directory.appending(path: "session.corrupt-\(stamp).json")
        try? FileManager.default.moveItem(at: sessionFile, to: aside)
        return .unreadable(reason: reason)
    }

    // MARK: PaneTranscripts

    public func keep(_ scrollback: Scrollback, for pane: PaneID) throws(SessionArchiveError) {
        let file = scrollbackFile(for: pane)
        let payload = Data([scrollback.format == .vt ? Self.vtMarker : Self.plainMarker]) + Data(scrollback.text.utf8)
        do {
            try write(try LZFSECodec.compress(payload), to: file)
        } catch let failure as LZFSECodec.Failure {
            throw .writeFailed(file: file.lastPathComponent, reason: failure.operation)
        } catch let error as SessionArchiveError {
            throw error
        } catch {
            throw .writeFailed(file: file.lastPathComponent, reason: String(describing: error))
        }
    }

    public func scrollback(of pane: PaneID) -> Scrollback? {
        guard let stored = try? Data(contentsOf: scrollbackFile(for: pane)),
            let payload = try? LZFSECodec.decompress(stored), let marker = payload.first
        else { return nil }
        let text = String(decoding: payload.dropFirst(), as: UTF8.self)
        return Scrollback(text: text, format: marker == Self.vtMarker ? .vt : .plain)
    }

    public func forget(allExcept panes: Set<PaneID>) {
        let keep = Set(panes.map(\.description))
        prune(scrollbackDirectory, keeping: keep, suffix: ".lzfse")
        prune(files.historyDirectory, keeping: keep, suffix: ".zsh_history")
    }

    /// First byte of a stored scrollback: its format.
    private static let vtMarker = UInt8(ascii: "V")
    private static let plainMarker = UInt8(ascii: "P")

    private func scrollbackFile(for pane: PaneID) -> URL { scrollbackDirectory.appending(path: "\(pane).lzfse") }

    private func prune(_ folder: URL, keeping ids: Set<String>, suffix: String) {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path(percentEncoded: false))) ?? []
        for name in names where name.hasSuffix(suffix) && !ids.contains(String(name.dropLast(suffix.count))) {
            try? FileManager.default.removeItem(at: folder.appending(path: name))
        }
    }

    // MARK: NamedLayouts

    public func save(_ layout: WorkspaceSnapshot, as name: LayoutName) throws(SessionArchiveError) {
        let file = layoutFile(name)
        try write(encoded(layout, file: file), to: file)
    }

    public func layout(named name: LayoutName) throws(SessionArchiveError) -> WorkspaceSnapshot {
        guard let data = try? Data(contentsOf: layoutFile(name)),
            let layout = try? decoder.decode(WorkspaceSnapshot.self, from: data)
        else { throw .notFound(name: name.rawValue) }
        return layout
    }

    public func names() -> [LayoutName] {
        let names =
            (try? FileManager.default.contentsOfDirectory(atPath: layoutsDirectory.path(percentEncoded: false))) ?? []
        return names.filter { $0.hasSuffix(".json") }.compactMap { try? LayoutName(String($0.dropLast(5))) }
            .sorted { $0.rawValue.localizedStandardCompare($1.rawValue) == .orderedAscending }
    }

    private func layoutFile(_ name: LayoutName) -> URL { layoutsDirectory.appending(path: "\(name.rawValue).json") }

    // MARK: RestorePreferenceStore

    private struct Preferences: Codable {
        var restore: RestorePreference
    }

    public func current() -> RestorePreference {
        guard let data = try? Data(contentsOf: preferencesFile),
            let preferences = try? decoder.decode(Preferences.self, from: data)
        else { return .ask }
        return preferences.restore
    }

    public func set(_ preference: RestorePreference) throws(SessionArchiveError) {
        try write(encoded(Preferences(restore: preference), file: preferencesFile), to: preferencesFile)
    }

    // MARK: Files

    private func encoded(_ value: some Encodable, file: URL) throws(SessionArchiveError) -> Data {
        do {
            return try encoder.encode(value)
        } catch {
            throw .writeFailed(file: file.lastPathComponent, reason: String(describing: error))
        }
    }

    private func write(_ data: Data, to file: URL) throws(SessionArchiveError) {
        do {
            try FileManager.default.createDirectory(
                at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            try FileManager.default.createDirectory(
                at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        } catch {
            throw .writeFailed(file: directory.lastPathComponent, reason: String(describing: error))
        }
        do {
            try AtomicFile.write(data, to: file)
        } catch {
            throw .writeFailed(file: file.lastPathComponent, reason: error.reason)
        }
    }
}
