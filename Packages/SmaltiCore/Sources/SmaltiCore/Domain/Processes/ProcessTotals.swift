/// The "Your processes" card: how many, their CPU and memory, and the part that came from Smalti's panes.
public struct ProcessTotals: Equatable, Sendable {
    public let count: Int
    public let hidden: Int
    /// Nil until a second sample gives CPU use.
    public let cpu: Double?
    public let memory: UInt64
    public let paneMemory: UInt64
    public let memoryTotal: UInt64

    public static func of(
        _ sample: ProcessSample, cpu: [ProcessIdentity: Double], attribution: PaneAttribution
    ) -> ProcessTotals {
        let own = sample.records.filter(\.isOwn)
        let used = own.compactMap { cpu[$0.identity] }
        return ProcessTotals(
            count: own.count, hidden: sample.hiddenCount, cpu: used.isEmpty ? nil : used.reduce(0, +),
            memory: own.reduce(0) { $0 + $1.memory },
            paneMemory: own.filter { attribution.pane(of: $0.pid) != nil }.reduce(0) { $0 + $1.memory },
            memoryTotal: sample.memoryTotal)
    }
}
