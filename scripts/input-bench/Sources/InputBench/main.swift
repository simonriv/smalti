import FigCompletionAdapter
import FileSessionAdapter
import Foundation
import GhosttyAdapter
import IPCAdapter
import ProjectContextAdapter
import SmaltiCore

// Usage: input-bench [--real-history] [--keystrokes N]
// Synthetic: 50,000 entries (fixed seed, Zipf over 3,000 commands in 400 directories). --real-history: the user's
// ~/.zsh_history, read-only and only in memory (never written anywhere), as the history and as what is typed.
let arguments = CommandLine.arguments
let usesRealHistory = arguments.contains("--real-history")
/// F5.6 C1: also highlight every line, as the app does (`LineAnswers`), and time the first highlight painted.
let highlights = arguments.contains("--highlight")
let keystrokes = arguments.firstIndex(of: "--keystrokes").flatMap { Int(arguments[$0 + 1]) } ?? 2_000
let root = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
let work = FileManager.default.temporaryDirectory.appending(path: "smalti-input-bench-\(UUID().uuidString.prefix(8))")
try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: work) }

// MARK: History

struct Generator {
    private var state: UInt64 = 0x5eed_f4_c1

    mutating func next() -> UInt64 {
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return state >> 33
    }

    /// Index in 0..<count with a Zipf-like skew (frequent commands first).
    mutating func zipf(_ count: Int) -> Int {
        let uniform = Double(next() % 1_000_000) / 1_000_000
        return min(Int(pow(Double(count), uniform)) - 1, count - 1)
    }
}

let verbs = ["git", "npm", "swift", "make", "docker", "kubectl", "brew", "cd", "ls", "cat", "rg", "gh", "python3"]
let objects = [
    "status", "commit -m wip", "push", "pull --rebase", "checkout main", "run dev", "test", "build", "logs -f",
    "get pods",
    "install", "src", "README.md", "TODO", "pr list", "-m http.server",
]
func syntheticCommands() -> [String] {
    var generator = Generator()
    return (0..<3_000).map { index in
        let verb = verbs[Int(generator.next() % UInt64(verbs.count))]
        let object = objects[Int(generator.next() % UInt64(objects.count))]
        return "\(verb) \(object) \(index)"
    }
}

func realCommands() throws -> [String] {
    let file = FileManager.default.homeDirectoryForCurrentUser.appending(path: ".zsh_history")
    let data = try Data(contentsOf: file)
    return String(decoding: data, as: UTF8.self).split(separator: "\n").map { line in
        // EXTENDED_HISTORY lines start with ": <time>:<duration>;".
        guard line.hasPrefix(": "), let semicolon = line.firstIndex(of: ";") else { return String(line) }
        return String(line[line.index(after: semicolon)...])
    }.filter { !$0.isEmpty && $0.utf8.count < 500 }
}

let commands = usesRealHistory ? try realCommands() : syntheticCommands()
var generator = Generator()
let pane = PaneID()
let directories = (0..<400).map { "/bench/project-\($0)" }
let entryCount = usesRealHistory ? min(commands.count, 50_000) : 50_000
let entries = (0..<entryCount).map { index in
    HistoryEntry(
        command: usesRealHistory
            ? commands[commands.count - entryCount + index] : commands[generator.zipf(commands.count)],
        directory: directories[generator.zipf(directories.count)], exit: 0, duration: 0.1,
        date: Date(timeIntervalSinceNow: -Double(entryCount - index) * 60), pane: pane)
}
let historyFile = work.appending(path: "history.jsonl")
let encoder = JSONEncoder()
var lines = Data()
for entry in entries {
    lines.append(try encoder.encode(entry))
    lines.append(UInt8(ascii: "\n"))
}
try lines.write(to: historyFile)

// MARK: Session and server

let specs = FigSpecs(user: work.appending(path: "completions"), runner: GeneratorRunner(timeout: .seconds(1)))
let session = InputSession(
    ports: InputSession.Ports(
        history: FileCommandHistory(file: historyFile, limit: 100_000), project: FileProjectContext(),
        completions: specs, predictor: HeuristicPredictor()),
    settings: .standard, clock: { Date() })
let highlighter = highlights ? HighlightLine(paths: FileSystemPathFacts(), completions: specs) : nil
let loadStart = ContinuousClock.now
await session.start()
let loadTime = ContinuousClock.now - loadStart

final class Timings: @unchecked Sendable {
    private let lock = NSLock()
    private var domain: [Double] = []

    func add(_ milliseconds: Double) { lock.withLock { domain.append(milliseconds) } }
    var all: [Double] { lock.withLock { domain } }
}
let timings = Timings()
let directory = directories[0]
let socket = "/tmp/smalti-bench-\(UUID().uuidString.prefix(8)).sock"
let style = SmaltiMessage.highlightStyle(Theme.obsidian.highlightPalette)
let server = try InputSocketServer(socketFile: URL(filePath: socket)) { connection, message in
    Task { @MainActor in
        let start = ContinuousClock.now
        if case .line(let seq, let line) = message.message, let highlighter {
            // The app's path (F5.6): ghost and highlight each sent when ready.
            await LineAnswers(session: session, highlighter: highlighter).answer(
                HighlightRequest(line: line, seq: seq, directory: directory, home: "/bench"), pane: pane,
                channel: LineChannel(send: { connection.send($0) }, isLatest: { _ in true }))
        } else {
            if case .hello = message.message, highlights { connection.send(style) }
            let reply = await InputRouting.respond(
                to: message.message, pane: pane, directory: directory, session: session)
            if case .send(let messages) = reply { messages.forEach { connection.send($0) } }
        }
        if case .line = message.message {
            let elapsed = ContinuousClock.now - start
            timings.add(Double(elapsed.components.attoseconds) / 1e15 + Double(elapsed.components.seconds) * 1000)
        }
    }
}
defer { server.stop() }

// MARK: zsh

let log = work.appending(path: "zsh.log")
let user = work.appending(path: "user")
try FileManager.default.createDirectory(at: user, withIntermediateDirectories: true)
try """
zmodload zsh/datetime
PS1='b%% '
functions[_bench_send]=$functions[_smalti_input_send]
_smalti_input_send() {
    [[ $1 == line$'\\t'* ]] && print -r -- "S ${${1#line$'\\t'}%%$'\\t'*} $EPOCHREALTIME" >> \(log.path(percentEncoded: false))
    _bench_send "$@"
}
functions[_bench_apply]=$functions[_smalti_input_apply]
_smalti_input_apply() {
    _bench_apply "$@"
    [[ $1 == suggest$'\\t'* ]] && print -r -- "P ${${1#suggest$'\\t'}%%$'\\t'*} $EPOCHREALTIME" >> \(log.path(percentEncoded: false))
    [[ $1 == highlight$'\\t'* ]] && print -r -- "H ${${1#highlight$'\\t'}%%$'\\t'*} $EPOCHREALTIME" >> \(log.path(percentEncoded: false))
}
""".write(to: user.appending(path: ".zshrc"), atomically: true, encoding: .utf8)
let smalti = try SmaltiZshEnv.install(in: work.appending(path: "smalti"))
let zsh = Process()
zsh.executableURL = URL(filePath: "/usr/bin/script")
zsh.arguments = ["-q", "/dev/null", "/bin/zsh", "-d", "-i"]
zsh.environment = [
    "HOME": work.path(percentEncoded: false), "TERM": "xterm-256color", "LANG": "en_US.UTF-8", "TMUX": "bench",
    "PATH": "/usr/bin:/bin",
    "ZDOTDIR": root.appending(
        path: "Packages/GhosttyAdapter/Frameworks/ghostty-resources/ghostty/shell-integration/zsh"
    ).path(percentEncoded: false),
    "GHOSTTY_ZSH_ZDOTDIR": smalti.path(percentEncoded: false), "SMALTI_USER_ZDOTDIR": user.path(percentEncoded: false),
    "SMALTI_INPUT_SOCKET": socket, "SMALTI_PANE_ID": pane.description,
]
let input = Pipe()
let output = Pipe()
zsh.standardInput = input
zsh.standardOutput = output
zsh.standardError = output
output.fileHandleForReading.readabilityHandler = { _ = $0.availableData }
try zsh.run()
try await Task.sleep(for: .seconds(1))

// Keystrokes: prefixes of commands from the history, one character at a time, ⌃U between lines.
var typed = 0
var pick = Generator()
while typed < keystrokes {
    let command = commands[pick.zipf(commands.count)]
    for character in command.prefix(24) where typed < keystrokes {
        input.fileHandleForWriting.write(Data(String(character).utf8))
        typed += 1
        try await Task.sleep(for: .milliseconds(25))
    }
    input.fileHandleForWriting.write(Data([0x15]))
    try await Task.sleep(for: .milliseconds(25))
}
try await Task.sleep(for: .seconds(1))
zsh.terminate()

// MARK: Results

let events = (try? String(contentsOf: log, encoding: .utf8)) ?? ""
var sent: [String: Double] = [:]
var endToEnd: [Double] = []
var highlightEndToEnd: [Double] = []
var highlighted: Set<String> = []
for line in events.split(separator: "\n") {
    let parts = line.split(separator: " ")
    guard parts.count == 3, let time = Double(parts[2]) else { continue }
    let seq = String(parts[1])
    switch parts[0] {
    case "S": sent[seq] = time
    case "P": if let start = sent[seq] { endToEnd.append((time - start) * 1000) }
    case "H":
        // Only the first highlight of a line: a follow-up repaints, it does not answer the keystroke.
        if let start = sent[seq], highlighted.insert(seq).inserted { highlightEndToEnd.append((time - start) * 1000) }
    default: break
    }
}

func percentile(_ values: [Double], _ fraction: Double) -> Double {
    guard !values.isEmpty else { return .nan }
    let sorted = values.sorted()
    return sorted[min(Int(Double(sorted.count) * fraction), sorted.count - 1)]
}
func format(_ value: Double) -> String { String(format: "%.2f", value) }
let domain = timings.all
print(
    "BENCH history=\(entryCount)\(usesRealHistory ? " (real)" : "") load=\(loadTime) keystrokes=\(typed)",
    "e2e n=\(endToEnd.count) p50=\(format(percentile(endToEnd, 0.5))) p95=\(format(percentile(endToEnd, 0.95)))",
    "p99=\(format(percentile(endToEnd, 0.99))) ms;",
    "domain n=\(domain.count) p50=\(format(percentile(domain, 0.5))) p99=\(format(percentile(domain, 0.99))) ms;",
    highlights
        ? "highlight n=\(highlightEndToEnd.count) p50=\(format(percentile(highlightEndToEnd, 0.5)))"
            + " p95=\(format(percentile(highlightEndToEnd, 0.95))) p99=\(format(percentile(highlightEndToEnd, 0.99))) ms"
        : "highlight off")
