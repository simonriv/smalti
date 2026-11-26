import Darwin
import XCTest

/// F8: the processes the UI tests start in a pane, and the only ones they ever stop. A Python script written to
/// the test's temporary folder listens on 127.0.0.1 on an ephemeral port (never the firewall's business) and writes
/// "<pid> <port>" to `$SMALTI_UITEST_OUT`; with `ignoringTerm` it outlives SIGTERM.
struct PaneListener {
    let script: URL

    init(outputFile: URL, ignoringTerm: Bool = false) throws {
        script = outputFile.deletingLastPathComponent()
            .appending(path: "smalti-f8-listener-\(UUID().uuidString.prefix(8)).py")
        let ignore = ignoringTerm ? "signal.signal(signal.SIGTERM, signal.SIG_IGN)\n" : ""
        let source = """
            import os, signal, socket, time
            \(ignore)s = socket.socket(); s.bind(("127.0.0.1", 0)); s.listen()
            open(os.environ["SMALTI_UITEST_OUT"], "w").write(f"{os.getpid()} {s.getsockname()[1]}")
            time.sleep(600)
            """
        try source.write(to: script, atomically: true, encoding: .utf8)
    }

    var name: String { script.lastPathComponent }

    /// Started from the pane's shell, so the pane is its parent and its terminal.
    func command() -> String { "python3 \(script.path(percentEncoded: false))" }

    /// The pid and port it wrote, once it wrote them.
    static func read(_ file: URL) -> (pid: Int32, port: Int)? {
        guard let text = try? String(contentsOf: file, encoding: .utf8) else { return nil }
        let parts = text.split(separator: " ")
        guard parts.count == 2, let pid = Int32(parts[0]), let port = Int(parts[1]) else { return nil }
        return (pid, port)
    }

    static func isAlive(_ pid: Int32) -> Bool {
        kill(pid, 0) == 0
    }

    /// Ends what the test started if it is still there and still runs this test's script; nothing else.
    func end(_ pid: Int32?) {
        defer { try? FileManager.default.removeItem(at: script) }
        guard let pid, Self.isAlive(pid), Self.arguments(of: pid).contains(script.path(percentEncoded: false)) else {
            return
        }
        kill(pid, SIGKILL)
    }

    /// What the process was started with (`KERN_PROCARGS2`, readable for one's own processes), NUL-separated
    /// arguments joined by spaces.
    static func arguments(of pid: Int32) -> String {
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var size = 0
        guard sysctl(&mib, 3, nil, &size, nil, 0) == 0, size > 0 else { return "" }
        var buffer = [UInt8](repeating: 0, count: size)
        guard sysctl(&mib, 3, &buffer, &size, nil, 0) == 0 else { return "" }
        return String(decoding: buffer.prefix(size).map { $0 == 0 ? 32 : $0 }, as: UTF8.self)
    }

    /// Read with `getpriority`, as anyone may (no child process from the test runner).
    static func nice(of pid: Int32) -> Int? {
        errno = 0
        let value = getpriority(PRIO_PROCESS, id_t(pid))
        return errno == 0 ? Int(value) : nil
    }

}

extension SmaltiUITestCase {
    func waitUntil(_ timeout: TimeInterval = 10, _ condition: @escaping () -> Bool) {
        wait(
            for: [XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in condition() }, object: nil)],
            timeout: timeout)
    }

    /// Runs the listener in the focused pane and waits for its pid and port.
    func start(_ listener: PaneListener) -> (pid: Int32, port: Int) {
        app.run(listener.command())
        let file = outputFile!
        waitUntil { PaneListener.read(file) != nil }
        guard let started = PaneListener.read(file) else {
            XCTFail("the listener did not start")
            return (0, 0)
        }
        return started
    }

    func openProcesses() {
        app.typeKey("m", modifierFlags: [.command, .shift])
        XCTAssertTrue(app.element("smalti.processes").waitForExistence(timeout: 5))
    }

    func openPorts() {
        app.typeKey("u", modifierFlags: [.command, .shift])
        XCTAssertTrue(app.element("smalti.processes").waitForExistence(timeout: 5))
    }

    /// Typed into the view's filter (XCUITest types a space as ⌃Space on the Latin American layout: no spaces).
    func filter(_ text: String) {
        app.typeText(text)
    }

    func notice() -> String { app.element("smalti.processes.notice").value as? String ?? "" }
}
