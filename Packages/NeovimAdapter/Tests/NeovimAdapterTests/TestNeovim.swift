import Foundation
import Testing

/// A Neovim for the tests: `nvim --clean --headless`, its own socket in a short temporary folder, killed with its
/// process group when the test ends. Never the user's config.
final class TestNeovim {
    static var isAvailable: Bool { binary != nil }
    static let binary = ["/opt/homebrew/bin/nvim", "/usr/local/bin/nvim"].first {
        FileManager.default.isExecutableFile(atPath: $0)
    }

    let folder: URL
    let socket: String
    private let process = Process()

    init(arguments: [String] = [], environment: [String: String] = [:]) throws {
        folder = URL(filePath: "/private/tmp/smalti-nvim-\(UUID().uuidString.prefix(8))")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        socket = folder.appending(path: "s").path
        process.executableURL = URL(filePath: try #require(Self.binary))
        process.arguments = ["--clean", "--headless", "--listen", socket] + arguments
        process.environment = [
            "HOME": folder.path, "XDG_CONFIG_HOME": folder.appending(path: "config").path,
            "XDG_DATA_HOME": folder.appending(path: "data").path,
            "XDG_STATE_HOME": folder.appending(path: "state").path,
            "PATH": "/opt/homebrew/bin:/usr/bin:/bin",
        ].merging(environment) { $1 }
        process.standardInput = Pipe()
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        let deadline = Date().addingTimeInterval(5)
        while !FileManager.default.fileExists(atPath: socket), Date() < deadline { Thread.sleep(forTimeInterval: 0.05) }
    }

    deinit {
        if process.isRunning { process.terminate() }
        let deadline = Date().addingTimeInterval(2)
        while process.isRunning, Date() < deadline { Thread.sleep(forTimeInterval: 0.05) }
        if process.isRunning { kill(process.processIdentifier, SIGKILL) }
        try? FileManager.default.removeItem(at: folder)
    }
}
