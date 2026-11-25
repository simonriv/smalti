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

/// The observatory's words, as the board writes them.
public enum ObservatoryTexts {
    /// The board's footnote, with OpenCode's database since F6.
    public static let footnote =
        "Datos: hooks y transcripts de Claude Code, base de OpenCode y API local de Ollama. El costo es estimado."

    /// "2 trabajando · 1 esperando" (the board's summary card says "esperando"), "· 1 error" only with errors.
    public static func sessions(_ summary: ObservatoryReport.Summary) -> String {
        let base = "\(summary.working) trabajando · \(summary.waiting) esperando"
        return summary.failed > 0 ? "\(base) · \(summary.failed) error" : base
    }

    public static func cache(_ summary: ObservatoryReport.Summary) -> String {
        summary.cacheShare.map { "\(ObservatoryFormat.percent($0)) desde caché" } ?? "sin entrada"
    }

    public static func peak(_ summary: ObservatoryReport.Summary, timeZone: TimeZone) -> String {
        guard let peak = summary.peak else { return "sin salida" }
        return
            "pico \(ObservatoryFormat.count(peak.output))/min · \(ObservatoryFormat.clock(peak.at, timeZone: timeZone))"
    }

    public static func cost(_ summary: ObservatoryReport.Summary) -> String {
        let unpriced = summary.cost.unpricedModels.count
        // The warning replaces "incluido en tu plan": the card is one line, and a missing price must be read.
        guard unpriced > 0 else { return "estimado · incluido en tu plan" }
        return "estimado · sin precio para \(unpriced) \(unpriced == 1 ? "modelo" : "modelos")"
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

    public static func state(_ kind: AgentStateKind) -> String {
        switch kind {
        case .working: "trabajando"
        case .waiting: "te espera"
        case .failed: "error"
        case .stopped: "detenida"
        }
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
