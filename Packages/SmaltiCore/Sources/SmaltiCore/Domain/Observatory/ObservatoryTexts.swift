import Foundation

/// A tool's result in the activity list: "1.8s" or "ok" in green, "exit 1" or "error" in red.
public struct ToolResultText: Equatable, Sendable {
    public let text: String
    public let isFailure: Bool

    public init(text: String, isFailure: Bool) {
        self.text = text
        self.isFailure = isFailure
    }
}

/// The observatory's sentences, built from `ObservatoryCopy` (F7.7).
public enum ObservatoryTexts {
    public static func footnote(status: TelemetryStatus, hasTelemetry: Bool, copy: ObservatoryCopy) -> String {
        if status == .configuredByUser { return copy.footnoteTelemetryElsewhere }
        return hasTelemetry ? copy.footnoteWithTelemetry : copy.footnote
    }

    /// "2 trabajando · 1 esperando" (the board's summary card says "esperando"), "· 1 error" only with errors.
    public static func sessions(_ summary: ObservatoryReport.Summary, copy: ObservatoryCopy) -> String {
        let base = copy.sessions(["working": String(summary.working), "waiting": String(summary.waiting)])
        return summary.failed > 0 ? base + copy.sessionsFailed(["failed": String(summary.failed)]) : base
    }

    public static func cache(_ summary: ObservatoryReport.Summary, copy: ObservatoryCopy) -> String {
        summary.cacheShare.map { copy.fromCache(["percent": ObservatoryFormat.percent($0)]) } ?? copy.noInput
    }

    public static func peak(_ summary: ObservatoryReport.Summary, timeZone: TimeZone, copy: ObservatoryCopy) -> String {
        guard let peak = summary.peak else { return copy.noOutput }
        return copy.peak([
            "count": ObservatoryFormat.count(peak.output),
            "clock": ObservatoryFormat.clock(peak.at, timeZone: timeZone),
        ])
    }

    public static func cost(_ summary: ObservatoryReport.Summary, copy: ObservatoryCopy) -> String {
        let unpriced = summary.cost.unpricedModels.count
        // The warning replaces "incluido en tu plan": the card is one line, and a missing price must be read.
        guard unpriced > 0 else { return copy.costIncluded }
        return copy.costUnpriced(unpriced)
    }

    public static func result(of tool: RecentTool) -> ToolResultText {
        switch tool.outcome {
        case .succeeded(let duration):
            let text = tool.name == bash ? "\(oneDecimal(duration))s" : "ok"
            return ToolResultText(text: text, isFailure: false)
        case .failed(let code):
            return ToolResultText(text: code.map { "exit \($0)" } ?? "error", isFailure: true)
        }
    }

    public static func state(_ kind: AgentStateKind, copy: ObservatoryCopy) -> String {
        copy.states[kind] ?? kind.rawValue
    }

    /// "4.8k · 10:42" next to the chart's peak.
    public static func chartPeak(_ peak: OutputPeak, timeZone: TimeZone) -> String {
        "\(ObservatoryFormat.count(peak.output)) · \(ObservatoryFormat.clock(peak.at, timeZone: timeZone))"
    }

    private static let bash = "Bash"

    private static func oneDecimal(_ value: Double) -> String {
        let tenths = Int((value * 10).rounded())
        return "\(tenths / 10).\(tenths % 10)"
    }
}
