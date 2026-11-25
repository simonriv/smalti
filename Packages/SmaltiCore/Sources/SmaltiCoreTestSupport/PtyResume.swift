import Foundation

/// What a resume run left: whether the session's text appeared, the screen without escapes, and the processes
/// tied to the fixture's home that were still alive after cleaning up (should be none, spec F6 C16).
public struct PtyResumeResult: Sendable {
    public let found: Bool
    public let transcript: String
    public let leftovers: [Int32]
}

/// Runs a harness's real resume command in a terminal, the way a Smalti pane would type it, and waits for the
/// session's first message to show (spec F6, C2). `script(1)` gives the command a pseudo-terminal with a controlling
/// terminal, which full-screen programs need. Afterwards it kills the run and every process whose command line or
/// environment names `root` (Codex's app-server and OpenCode's service outlive their TUI).
public enum PtyResume {
    public struct Run: Sendable {
        public let command: String
        public let environment: [String: String]
        public let directory: URL
        public let needle: String
        public let root: URL
        /// Screens to answer on the way, by the text they show (Codex asks to trust the folder).
        public let answers: [String: String]
        public let timeout: TimeInterval

        public init(
            command: String, environment: [String: String], directory: URL, needle: String, root: URL,
            answers: [String: String] = [:], timeout: TimeInterval = 45
        ) {
            self.command = command
            self.environment = environment
            self.directory = directory
            self.needle = needle
            self.root = root
            self.answers = answers
            self.timeout = timeout
        }
    }

    /// The first executable called `name` in the usual install places, for skipping when a harness is missing.
    public static func binary(_ name: String) -> URL? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return ["/opt/homebrew/bin", "/usr/local/bin", "\(home)/.local/bin", "/usr/bin"]
            .map { URL(filePath: "\($0)/\(name)") }
            .first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    public static func run(_ run: Run) throws -> PtyResumeResult {
        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/script")
        process.arguments = [
            "-q", "/dev/null", "/bin/zsh", "-f", "-c", "stty cols 120 rows 40 2>/dev/null; \(run.command)",
        ]
        process.environment = run.environment
        process.currentDirectoryURL = run.directory
        let input = Pipe()
        let output = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = output
        let screen = Screen()
        output.fileHandleForReading.readabilityHandler = { handle in screen.append(handle.availableData) }
        try process.run()
        let found = wait(for: run, on: screen, answeringInto: input.fileHandleForWriting)
        output.fileHandleForReading.readabilityHandler = nil
        stop(process, root: run.root)
        return PtyResumeResult(found: found, transcript: screen.plain, leftovers: processes(naming: run.root))
    }

    private static func wait(for run: Run, on screen: Screen, answeringInto input: FileHandle) -> Bool {
        let deadline = Date().addingTimeInterval(run.timeout)
        var answered: Set<String> = []
        while Date() < deadline {
            let plain = screen.compact
            if plain.contains(compacted(run.needle)) { return true }
            for (prompt, keys) in run.answers where !answered.contains(prompt) && plain.contains(compacted(prompt)) {
                answered.insert(prompt)
                try? input.write(contentsOf: Data(keys.utf8))
            }
            Thread.sleep(forTimeInterval: 0.2)
        }
        return false
    }

    private static func stop(_ process: Process, root: URL) {
        for signal in [SIGTERM, SIGKILL] {
            if process.isRunning { kill(process.processIdentifier, signal) }
            for pid in processes(naming: root) { kill(pid, signal) }
            let until = Date().addingTimeInterval(2)
            while Date() < until, process.isRunning || !processes(naming: root).isEmpty {
                Thread.sleep(forTimeInterval: 0.1)
            }
        }
    }

    /// Processes of this user whose command line or environment names `root`.
    public static func processes(naming root: URL) -> [Int32] {
        let ps = Process()
        ps.executableURL = URL(filePath: "/bin/ps")
        ps.arguments = ["-x", "-E", "-o", "pid=,command="]
        let pipe = Pipe()
        ps.standardOutput = pipe
        guard (try? ps.run()) != nil else { return [] }
        let text = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        ps.waitUntilExit()
        let mine = ProcessInfo.processInfo.processIdentifier
        return text.split(separator: "\n").compactMap { line in
            guard line.contains(root.path) else { return nil }
            let pid = line.split(separator: " ", maxSplits: 1).first.flatMap { Int32($0) }
            return pid == mine || line.contains("/bin/ps") ? nil : pid
        }
    }

    static func compacted(_ text: String) -> String { text.filter { !$0.isWhitespace } }

    /// The terminal's output so far; escapes removed for matching.
    final class Screen: @unchecked Sendable {
        private let lock = NSLock()
        private var bytes = Data()

        func append(_ data: Data) {
            lock.lock()
            bytes.append(data)
            lock.unlock()
        }

        var plain: String {
            lock.lock()
            defer { lock.unlock() }
            let text = String(decoding: bytes, as: UTF8.self)
            return text.replacing(
                /\u{1B}\[[0-9;?<>=$]*[A-Za-z~]|\u{1B}\][^\u{07}\u{1B}]*(\u{07}|\u{1B}\\)|\u{1B}[()=>78]/, with: "")
        }

        var compact: String { PtyResume.compacted(plain) }
    }
}
