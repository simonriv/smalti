import Foundation

/// Measurement hook for B8 (and later F4): `-SmaltiLatencyProbe <file>` schedules a 5 ms timer on the main thread
/// and records how late each tick fires. A late tick is time the main thread could not answer input; on quit the
/// worst delay and the count above one 60 Hz frame are written as JSON. Off unless the argument is given.
@MainActor
final class LatencyProbe {
    static let launchArgument = "SmaltiLatencyProbe"
    private static let interval: Duration = .milliseconds(5)
    /// One frame at 60 Hz: the spec's limit for a main-thread block (B8).
    private static let frameBudget: Duration = .milliseconds(16)

    private let output: URL
    private var timer: Timer?
    private let started = ContinuousClock.now
    private var expected = ContinuousClock.now
    /// Each delay over budget as [milliseconds since start, delay in milliseconds], to match against what ran.
    private var lateTicks: [[Double]] = []
    private var worst: Duration = .zero
    private var overBudget = 0
    private var ticks = 0

    init?(arguments: UserDefaults = .standard) {
        guard let path = arguments.string(forKey: Self.launchArgument), !path.isEmpty else { return nil }
        output = URL(filePath: path)
    }

    func start() {
        expected = .now + Self.interval
        let timer = Timer(timeInterval: 0.005, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func finish() {
        timer?.invalidate()
        let report: [String: Any] = [
            "ticks": ticks, "worstDelayMs": Self.milliseconds(worst), "delaysOver16Ms": overBudget,
            "lateTicks": lateTicks,
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: report, options: [.sortedKeys]) else { return }
        try? data.write(to: output)
    }

    private func tick() {
        let now = ContinuousClock.now
        let delay = now - expected
        ticks += 1
        worst = max(worst, delay)
        if delay > Self.frameBudget {
            overBudget += 1
            lateTicks.append([Self.milliseconds(now - started), Self.milliseconds(delay)])
        }
        expected = now + Self.interval
    }

    private static func milliseconds(_ duration: Duration) -> Double {
        Double(duration.components.seconds) * 1000 + Double(duration.components.attoseconds) / 1e15
    }
}
