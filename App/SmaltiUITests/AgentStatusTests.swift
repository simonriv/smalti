import XCTest

/// C11: a log of Claude Code hook events, replayed through the bundled `smalti` CLI from inside a pane, drives the
/// pane's state, the strip and the notifications exactly as the spec's transition table says.
final class AgentStatusTests: SmaltiUITestCase {
    override var launchesAtSetUp: Bool { false }

    private var notices: URL { outputFile.appendingPathExtension("notices") }

    private struct Step: Decodable {
        let hook: String
        let expect: String
        let hidden: Bool?
        let payload: [String: AnyJSON]
    }

    func testRecordedHookLogDrivesTheUI() throws {
        let app = XCUIApplication.isolatedSmalti()
        app.launchArguments += ["-SmaltiNotificationLog", notices.path(percentEncoded: false)]
        launch(app)

        for step in try steps() {
            if step.hidden == true {
                sendLater(step)
                app.typeKey("n", modifierFlags: [.control, .command])
                waitForShells(count: 1)
                expectCounter("waiting", "1 te espera")
                app.typeKey("1", modifierFlags: .control)
            } else {
                send(step)
            }
            expectStatus(step.expect, after: step.hook)
        }

        let bodies = noticeBodies()
        XCTAssertEqual(bodies, ["pide permiso para `pnpm test`", "terminó y te espera", "error: API error 529"])
    }

    /// C15: ⌘J goes to the agent that has waited longest, in another workspace.
    func testJumpGoesToLongestWaitingPaneInAnotherWorkspace() throws {
        let app = XCUIApplication.isolatedSmalti()
        launch(app)
        let steps = try steps()
        send(steps[4])  // PermissionRequest: waiting first
        app.typeKey("n", modifierFlags: [.control, .command])
        waitForShells(count: 1)
        send(steps[8])  // Stop in the second workspace: waiting later
        expectCounter("waiting", "2 te espera")

        app.typeKey("j", modifierFlags: .command)

        let first = app.elements("smalti.workspace").element(boundBy: 0)
        let active = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == 'active'"), object: first)
        wait(for: [active], timeout: 5)
    }

    /// F4.5: ⌘J looks in every window and brings the one with the waiting agent to the front.
    func testJumpBringsTheWindowOfTheWaitingAgentToTheFront() throws {
        let app = XCUIApplication.isolatedSmalti()
        launch(app)
        send(try steps()[4])  // PermissionRequest: this window's pane waits
        expectStatus("waiting", after: "PermissionRequest")
        app.typeKey("n", modifierFlags: .command)
        waitForShells(count: 2)

        app.typeKey("j", modifierFlags: .command)

        let front = app.windows.matching(identifier: "smalti.window").element(boundBy: 0)
        let status = front.descendants(matching: .any).matching(identifier: "smalti.paneStatus").firstMatch
        let waiting = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == 'waiting'"), object: status)
        wait(for: [waiting], timeout: 5)
    }

    // MARK: - Helpers

    private func steps() throws -> [Step] {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "claude-hooks-2.1.330", withExtension: "jsonl"))
        return try String(contentsOf: url, encoding: .utf8).split(separator: "\n").map {
            try JSONDecoder().decode(Step.self, from: Data($0.utf8))
        }
    }

    private func command(for step: Step) throws -> String {
        let payload = String(decoding: try JSONEncoder().encode(step.payload), as: UTF8.self)
        return "printf '%s' '\(payload)' | \"$SMALTI_CLI\" event \(step.hook)"
    }

    private func send(_ step: Step) {
        guard let line = try? command(for: step) else { return XCTFail("bad step \(step.hook)") }
        app.run(line)
    }

    /// Runs the hook two seconds from now, so the pane is hidden when it arrives.
    private func sendLater(_ step: Step) {
        guard let line = try? command(for: step) else { return XCTFail("bad step \(step.hook)") }
        app.run("(sleep 2; \(line)) &")
    }

    private func expectStatus(_ status: String, after hook: String) {
        let dot = app.elements("smalti.paneStatus").firstMatch
        let shown = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", status), object: dot)
        let result = XCTWaiter().wait(for: [shown], timeout: 6)
        XCTAssertEqual(result, .completed, "after \(hook) the pane should be \(status), is \(dot.value ?? "nil")")
    }

    private func expectCounter(_ kind: String, _ text: String) {
        let counter = app.element("smalti.counter.\(kind)")
        let shown = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", text), object: counter)
        wait(for: [shown], timeout: 6)
    }

    private func noticeBodies() -> [String] {
        let text = (try? String(contentsOf: notices, encoding: .utf8)) ?? ""
        return text.split(separator: "\n").compactMap {
            (try? JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: String])?["body"]
        }
    }
}

/// Any JSON value, to carry hook payloads through Codable unchanged.
enum AnyJSON: Codable {
    case string(String), number(Double), bool(Bool), object([String: AnyJSON]), array([AnyJSON]), null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([AnyJSON].self) {
            self = .array(value)
        } else {
            self = .object(try container.decode([String: AnyJSON].self))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }
}
