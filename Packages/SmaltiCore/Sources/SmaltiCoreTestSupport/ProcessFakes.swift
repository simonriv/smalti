import SmaltiCore

/// Hands out the queued samples in order and repeats the last one.
public actor FakeRunningProcesses: RunningProcesses {
    private var samples: [ProcessSample]
    private var delay = Duration.zero
    public private(set) var reads = 0

    public init(samples: [ProcessSample]) {
        self.samples = samples
    }

    public func queue(_ sample: ProcessSample) {
        samples.append(sample)
    }

    /// Every read takes this long, so a test can stop or close while one is on its way.
    public func slowDown(_ delay: Duration) {
        self.delay = delay
    }

    public func current() async -> ProcessSample {
        reads += 1
        if delay > .zero { try? await Task.sleep(for: delay) }
        guard samples.count > 1 else {
            return samples.first ?? ProcessSample(records: [], takenAt: 0, hiddenCount: 0, memoryTotal: 0)
        }
        return samples.removeFirst()
    }
}

public actor FakeListeningPorts: ListeningPorts {
    private var sockets: [ListeningSocket]
    public private(set) var reads = 0

    public init(sockets: [ListeningSocket] = []) {
        self.sockets = sockets
    }

    public func set(_ sockets: [ListeningSocket]) {
        self.sockets = sockets
    }

    public func current() async -> [ListeningSocket] {
        reads += 1
        return sockets
    }
}

/// Records every call; `failure` makes the next calls throw.
public actor FakeProcessControl: ProcessControl {
    public enum Call: Equatable, Sendable {
        case stop(ProcessIdentity)
        case forceStop(ProcessIdentity)
        case lowerPriority(ProcessIdentity, Int32)
    }

    public private(set) var calls: [Call] = []
    private var failure: ProcessControlError?

    public init() {}

    public func fail(with error: ProcessControlError?) {
        failure = error
    }

    public func stop(_ process: ProcessIdentity) async throws(ProcessControlError) {
        try record(.stop(process))
    }

    public func forceStop(_ process: ProcessIdentity) async throws(ProcessControlError) {
        try record(.forceStop(process))
    }

    public func lowerPriority(_ process: ProcessIdentity, to nice: Int32) async throws(ProcessControlError) {
        try record(.lowerPriority(process, nice))
    }

    private func record(_ call: Call) throws(ProcessControlError) {
        calls.append(call)
        if let failure { throw failure }
    }
}
