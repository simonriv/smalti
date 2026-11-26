import Foundation

/// Who a notice is about: the process's name and the chord that closes a pane (for the shell's reason).
public struct NoticeSubject: Equatable, Sendable {
    public let name: String
    public let closeKey: String

    public init(name: String, closeKey: String) {
        self.name = name
        self.closeKey = closeKey
    }

    var values: [String: String] { ["name": name, "close": closeKey] }
}

/// How the processes and ports views write their figures and phrases.
public enum ProcessFormat {
    /// "14.2%", "0.0%"; "—" before a second sample gives CPU.
    public static func cpu(_ value: Double?) -> String {
        guard let value else { return "—" }
        let tenths = Int((value * 10).rounded())
        return "\(tenths / 10).\(tenths % 10)%"
    }

    /// "412 MB", "1.2 GB": Activity Monitor's binary units.
    public static func memory(_ bytes: UInt64) -> String {
        ObservatoryFormat.gigabytes(bytes)
    }

    public static func state(_ state: ProcessState, texts: ProcessTexts) -> String {
        texts.states[state] ?? ""
    }

    public static func scope(_ scope: ListenScope, texts: ProcessTexts) -> String {
        switch scope {
        case .local: texts.local
        case .all: texts.all
        case .specific(let addresses): addresses.joined(separator: ", ")
        }
    }

    public static func priority(_ nice: Int32, texts: ProcessTexts) -> String {
        texts.priorityLevels[NicePriority.level(of: nice)]?(["nice": String(nice)]) ?? String(nice)
    }

    /// "~/dev/acme/web" under the home folder; the path as it is otherwise.
    public static func directory(_ path: String?, home: String) -> String {
        guard let path, !path.isEmpty else { return "—" }
        guard !home.isEmpty, path == home || path.hasPrefix(home + "/") else { return path }
        return "~" + path.dropFirst(home.count)
    }

    public static func started(_ date: Date, now: Date, texts: ProcessTexts) -> String {
        ElapsedPhrase.text(since: date, now: now, texts: texts.time)
    }

    /// The footer's notice for what pressing "Stop" or confirming did; nil when nothing needs saying.
    public static func notice(_ outcome: StopOutcome, for subject: NoticeSubject, texts: ProcessTexts) -> String? {
        let name = subject.name
        switch outcome {
        case .requested: return texts.requested(["name": name])
        case .waiting: return texts.waiting(["name": name])
        case .confirming: return nil
        case .forced: return texts.forced(["name": name])
        case .protected(let reason): return texts.reasons[reason]?(subject.values)
        case .failed(let error): return failure(error, name: name, texts: texts)
        }
    }

    public static func notice(_ outcome: PriorityOutcome, for subject: NoticeSubject, texts: ProcessTexts) -> String {
        let name = subject.name
        switch outcome {
        case .lowered(let nice): return texts.lowered(["name": name, "level": priority(nice, texts: texts)])
        case .alreadyLowest: return texts.alreadyLowest(["name": name])
        case .protected(let reason): return texts.reasons[reason]?(subject.values) ?? ""
        case .failed(let error): return failure(error, name: name, texts: texts)
        }
    }

    private static func failure(_ error: ProcessControlError, name: String, texts: ProcessTexts) -> String {
        switch error {
        case .gone: texts.gone(["name": name])
        case .notYours: texts.notYours(["name": name])
        case .refused(let code): texts.refused(["name": name, "code": String(code)])
        }
    }

    /// Notices that report a failure: the footer shows them in the error color.
    public static func isFailure(_ outcome: StopOutcome) -> Bool {
        if case .failed(let error) = outcome { return error != .gone }
        return false
    }
}
