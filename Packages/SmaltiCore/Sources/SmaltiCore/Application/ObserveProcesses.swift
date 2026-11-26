/// One refresh of the processes and ports views.
public struct ProcessesSnapshot: Sendable {
    public let sample: ProcessSample
    public let cpu: [ProcessIdentity: Double]
    public let sockets: [ListeningSocket]
    public let attribution: PaneAttribution

    public var alive: Set<ProcessIdentity> { Set(sample.records.map(\.identity)) }

    public func input(
        policy: StopPolicy, paneNames: [PaneID: String], phases: [ProcessIdentity: StopPhase]
    ) -> ProcessTableInput {
        ProcessTableInput(
            sample: sample, cpu: cpu, attribution: attribution, policy: policy, paneNames: paneNames, phases: phases)
    }

    public var totals: ProcessTotals { .of(sample, cpu: cpu, attribution: attribution) }
}

/// Reads processes and ports together and works out CPU use against the previous read. Only the open view calls
/// it: nothing samples while the view is closed (spec F8, C4).
@MainActor
public final class ObserveProcesses {
    private let processes: any RunningProcesses
    private let ports: any ListeningPorts
    private var previous: ProcessSample?

    public init(processes: any RunningProcesses, ports: any ListeningPorts) {
        self.processes = processes
        self.ports = ports
    }

    public func refresh(foregroundGroups: [PaneID: Int32]) async -> ProcessesSnapshot {
        async let sample = processes.current()
        async let sockets = ports.current()
        let current = await sample
        let cpu = CPUUsage.percentages(previous: previous, current: current)
        previous = current
        return ProcessesSnapshot(
            sample: current, cpu: cpu, sockets: await sockets,
            attribution: PaneAttribution(records: current.records, foregroundGroups: foregroundGroups))
    }

    /// On closing the view: the next opening starts without CPU, not with a delta across the time it was closed.
    public func reset() {
        previous = nil
    }
}
