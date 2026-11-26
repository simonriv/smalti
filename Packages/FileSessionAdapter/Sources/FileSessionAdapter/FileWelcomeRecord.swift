import Foundation
import SmaltiCore

/// `WelcomeRecord` as `welcome.json` in the app's state directory (F7.7), next to `session.json`. Any readable file
/// counts as done, a newer format included; the file is written once, atomically, readable only by the user.
public struct FileWelcomeRecord: WelcomeRecord {
    static let fileName = "welcome.json"
    static let formatVersion = 1

    private let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    private var file: URL { directory.appending(path: Self.fileName) }

    public var isDone: Bool {
        FileManager.default.fileExists(atPath: file.path(percentEncoded: false))
    }

    public func markDone() throws(WelcomeRecordError) {
        do {
            try FileManager.default.createDirectory(
                at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            try Data(#"{"version":\#(Self.formatVersion)}"#.utf8).write(to: file, options: .atomic)
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o600], ofItemAtPath: file.path(percentEncoded: false))
        } catch {
            throw .unwritable(path: file.path(percentEncoded: false), reason: error.localizedDescription)
        }
    }
}
