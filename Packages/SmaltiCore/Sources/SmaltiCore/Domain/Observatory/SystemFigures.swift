import Foundation

/// The "Sistema" card: CPU, GPU, unified memory and how it splits into the local model, the agents and the rest.
public struct SystemFigures: Equatable, Sendable {
    public struct Shares: Equatable, Sendable {
        public let model: Double
        public let agents: Double
        public let rest: Double

        public init(model: Double, agents: Double, rest: Double) {
            self.model = model
            self.agents = agents
            self.rest = rest
        }
    }

    public let title: String
    public let cpu: String
    public let gpu: String
    public let memory: String
    /// "modelo 6.1 · agentes 3.5 · resto 1.6 GB · presión media"; "modelo" only with a model loaded.
    public let split: String
    /// Fractions of the installed memory, for the segmented bar.
    public let shares: Shares

    public static func make(_ snapshot: ObservatorySnapshot) -> SystemFigures {
        let system = snapshot.system
        let model = loadedBytes(snapshot.localModels)
        return SystemFigures(
            title: "Sistema · \(system.machineName)",
            cpu: percent(system.cpu), gpu: percent(system.gpu),
            memory: system.memoryUsed.value.map { ObservatoryFormat.memory(used: $0, total: system.memoryTotal) }
                ?? StatusFigures.unavailable,
            split: splitText(system, model: model),
            shares: shares(system, model: model))
    }

    private static func percent(_ value: Reading<Double>) -> String {
        value.value.map { ObservatoryFormat.percent(Int($0.rounded())) } ?? StatusFigures.unavailable
    }

    private static func loadedBytes(_ report: LocalModelsReport) -> UInt64? {
        guard case .available(let loaded, _) = report, !loaded.isEmpty else { return nil }
        return loaded.reduce(0) { $0 + ($1.vramBytes ?? $1.bytes) }
    }

    private static func splitText(_ system: SystemSample, model: UInt64?) -> String {
        guard let used = system.memoryUsed.value else { return StatusFigures.unavailable }
        var parts: [String] = []
        if let model { parts.append("modelo \(ObservatoryFormat.gigabyteNumber(model))") }
        if let agents = system.agentsMemory.value {
            parts.append("agentes \(ObservatoryFormat.gigabyteNumber(agents))")
            parts.append("resto \(ObservatoryFormat.gigabyteNumber(rest(used: used, model: model, agents: agents))) GB")
        } else {
            parts.append("agentes \(StatusFigures.unavailable)")
        }
        let pressure = system.pressure.value?.rawValue ?? StatusFigures.unavailable
        return (parts + ["presión \(pressure)"]).joined(separator: " · ")
    }

    private static func rest(used: UInt64, model: UInt64?, agents: UInt64) -> UInt64 {
        let taken = (model ?? 0) + agents
        return used > taken ? used - taken : 0
    }

    private static func shares(_ system: SystemSample, model: UInt64?) -> Shares {
        let total = Double(max(system.memoryTotal, 1))
        guard let used = system.memoryUsed.value else { return Shares(model: 0, agents: 0, rest: 0) }
        let agents = system.agentsMemory.value ?? 0
        return Shares(
            model: Double(model ?? 0) / total, agents: Double(agents) / total,
            rest: Double(rest(used: used, model: model, agents: agents)) / total)
    }
}

/// The "Modelos locales · Ollama" card.
public enum LocalModelsFigures: Equatable, Sendable {
    public struct Row: Equatable, Sendable {
        public let name: String
        public let status: String
        public let isLoaded: Bool
        public let detail: String

        public init(name: String, status: String, isLoaded: Bool, detail: String) {
            self.name = name
            self.status = status
            self.isLoaded = isLoaded
            self.detail = detail
        }
    }

    case message(String)
    case models([Row])

    private static let contextUnit = 1_024

    public static func make(_ report: LocalModelsReport, now: Date) -> LocalModelsFigures {
        guard case .available(let loaded, let onDisk) = report else { return .message("Ollama no está corriendo") }
        let loadedNames = Set(loaded.map(\.name))
        let rows =
            loaded.map { Row(name: $0.name, status: "cargado", isLoaded: true, detail: loadedDetail($0)) }
            + onDisk.filter { !loadedNames.contains($0.name) }.map {
                Row(name: $0.name, status: "en disco", isLoaded: false, detail: diskDetail($0, now: now))
            }
        return rows.isEmpty ? .message("Sin modelos locales") : .models(rows)
    }

    private static func loadedDetail(_ model: LocalModel) -> String {
        let context = model.contextLength.map { "ctx \($0 / contextUnit)K" }
        return ([model.quantization, ObservatoryFormat.gigabytes(model.bytes), context].compactMap { $0 })
            .joined(separator: " · ")
    }

    private static func diskDetail(_ model: LocalModel, now: Date) -> String {
        let downloaded = model.downloadedAt.map { "descargado " + ObservatoryFormat.ago(now.timeIntervalSince($0)) }
        return ([ObservatoryFormat.gigabytes(model.bytes), downloaded].compactMap { $0 }).joined(separator: " · ")
    }
}
