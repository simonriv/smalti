import Foundation

/// The right side of the status bar: loaded local model, RAM, GPU and today's tokens.
public struct StatusFigures: Equatable, Sendable {
    public let localModel: String?
    public let ram: String
    public let gpu: String
    public let todayTokens: String

    public init(localModel: String?, ram: String, gpu: String, todayTokens: String) {
        self.localModel = localModel
        self.ram = ram
        self.gpu = gpu
        self.todayTokens = todayTokens
    }

    public static let unavailable = "no disponible"

    public static func make(_ snapshot: ObservatorySnapshot, calendar: Calendar) -> StatusFigures {
        let window = PeriodWindow(
            start: ObservatoryPeriod.today.start(now: snapshot.now, calendar: calendar), end: snapshot.now)
        let today = snapshot.activity.sessions.flatMap { window.usage(of: $0).values }.reduce(.zero, +)
        let system = snapshot.system
        return StatusFigures(
            localModel: loadedModel(snapshot.localModels),
            ram: "RAM "
                + (system.memoryUsed.value.map { ObservatoryFormat.memory(used: $0, total: system.memoryTotal) }
                    ?? unavailable),
            gpu: "GPU " + (system.gpu.value.map { ObservatoryFormat.percent(Int($0.rounded())) } ?? unavailable),
            todayTokens: "hoy \(ObservatoryFormat.count(today.inputTotal + today.output)) tokens")
    }

    private static func loadedModel(_ report: LocalModelsReport) -> String? {
        guard case .available(let loaded, _) = report, let model = loaded.first else { return nil }
        return "\(model.name) · \(ObservatoryFormat.gigabytes(model.bytes))"
    }
}

/// The pane header's model family and context load for the session running in it.
public struct PaneAgentDetail: Equatable, Sendable {
    public let family: String?
    public let context: ContextLoad

    public init(family: String?, context: ContextLoad) {
        self.family = family
        self.context = context
    }

    public static func make(sessionID: String, snapshot: ObservatorySnapshot) -> PaneAgentDetail {
        guard let activity = snapshot.activity.sessions.first(where: { $0.sessionID == sessionID }) else {
            return PaneAgentDetail(family: nil, context: .unavailable)
        }
        return PaneAgentDetail(
            family: activity.model?.family,
            context: ContextLoad.of(
                contextTokens: activity.contextTokens, model: activity.model, catalog: snapshot.catalog))
    }
}
