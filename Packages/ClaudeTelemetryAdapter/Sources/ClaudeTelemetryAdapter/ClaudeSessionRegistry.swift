import Darwin
import Foundation
import SmaltiCore

/// Whether a process is alive and when it started; the real one asks the kernel.
protocol ProcessProbe: Sendable {
    func isAlive(_ pid: Int32) -> Bool
    func startTime(of pid: Int32) -> Date?
}

struct DarwinProcessProbe: ProcessProbe {
    func isAlive(_ pid: Int32) -> Bool {
        kill(pid, 0) == 0 || errno == EPERM
    }

    func startTime(of pid: Int32) -> Date? {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size else { return nil }
        return Date(timeIntervalSince1970: Double(info.pbi_start_tvsec) + Double(info.pbi_start_tvusec) / 1_000_000)
    }
}

/// `LiveAgents` from `~/.claude/sessions/<pid>.json`. Only `*.json` files are opened: the `*.key` files beside them
/// are messaging keys and are never read. A PID counts as Claude only while it is alive and started when the file
/// says (`procStart`), so a reused PID never passes for a running session.
public struct ClaudeSessionRegistry: LiveAgents {
    private let sessions: URL
    private let processes: any ProcessProbe

    /// `procStart` is written to the second; the kernel keeps microseconds.
    private static let startTolerance: TimeInterval = 1
    private static let millisecondsPerSecond = 1_000.0

    public init(claudeHome: URL) {
        self.init(claudeHome: claudeHome, processes: DarwinProcessProbe())
    }

    init(claudeHome: URL, processes: any ProcessProbe) {
        sessions = claudeHome.appending(path: "sessions")
        self.processes = processes
    }

    public func running() async -> [RunningAgent] {
        let files = (try? FileManager.default.contentsOfDirectory(at: sessions, includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.pathExtension == "json" }.sorted { $0.path < $1.path }.compactMap(agent(in:))
    }

    private func agent(in file: URL) -> RunningAgent? {
        guard let data = try? Data(contentsOf: file),
            let record = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
            let pid = (record["pid"] as? NSNumber)?.int32Value, let session = record["sessionId"] as? String,
            !session.isEmpty, isRunning(pid, procStart: record["procStart"] as? String)
        else { return nil }
        let startedAt = (record["startedAt"] as? NSNumber).map {
            Date(timeIntervalSince1970: $0.doubleValue / Self.millisecondsPerSecond)
        }
        return RunningAgent(
            pid: pid, sessionID: session, cwd: record["cwd"] as? String ?? "",
            status: record["status"] as? String ?? "",
            startedAt: startedAt ?? Date())
    }

    private func isRunning(_ pid: Int32, procStart: String?) -> Bool {
        guard pid > 0, processes.isAlive(pid) else { return false }
        guard let procStart, let expected = Self.processStart(procStart) else { return true }
        guard let actual = processes.startTime(of: pid) else { return false }
        return abs(actual.timeIntervalSince(expected)) < Self.startTolerance
    }

    /// `procStart` is `ctime` text in UTC ("Mon Nov 23 04:35:02 2026", single-digit days padded or not).
    static func processStart(_ text: String) -> Date? {
        let words = text.split(separator: " ").map(String.init)
        guard words.count == 5, let month = months.firstIndex(of: words[1]), let day = Int(words[2]),
            let year = Int(words[4])
        else { return nil }
        let time = words[3].split(separator: ":").compactMap { Int($0) }
        guard time.count == 3 else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        return calendar.date(
            from: DateComponents(
                year: year, month: month + 1, day: day, hour: time[0], minute: time[1], second: time[2]))
    }

    private static let months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
}
