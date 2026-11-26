import Foundation
import SmaltiCore
import Testing

@Suite("ProcessFormat")
struct ProcessFormatTests {
    private let es = ProcessTexts.spanish
    private let en = ProcessTexts.english

    @Test(arguments: [
        (Double?.none, "—"), (0, "0.0%"), (14.24, "14.2%"), (14.25, "14.3%"), (150, "150.0%"), (0.04, "0.0%"),
    ])
    func cpu(value: Double?, text: String) {
        #expect(ProcessFormat.cpu(value) == text)
    }

    @Test func memoryUsesBinaryUnits() {
        #expect(ProcessFormat.memory(412 << 20) == "412 MB")
        #expect(ProcessFormat.memory(UInt64(1.5 * 1024 * 1024 * 1024)) == "1.5 GB")
    }

    @Test func scopes() {
        #expect(ProcessFormat.scope(.local, texts: es) == "solo local")
        #expect(ProcessFormat.scope(.all, texts: en) == "all")
        #expect(ProcessFormat.scope(.specific(["10.0.0.2", "10.0.0.3"]), texts: es) == "10.0.0.2, 10.0.0.3")
    }

    @Test func priorityLevels() {
        #expect(ProcessFormat.priority(0, texts: es) == "normal (0)")
        #expect(ProcessFormat.priority(5, texts: es) == "baja (5)")
        #expect(ProcessFormat.priority(20, texts: en) == "very low (20)")
        #expect(ProcessFormat.priority(-2, texts: en) == "high (-2)")
    }

    @Test func directoryAbbreviatesHome() {
        #expect(ProcessFormat.directory("/Users/ana/dev/web", home: "/Users/ana") == "~/dev/web")
        #expect(ProcessFormat.directory("/Users/ana", home: "/Users/ana") == "~")
        #expect(ProcessFormat.directory("/Users/anabel/x", home: "/Users/ana") == "/Users/anabel/x")
        #expect(ProcessFormat.directory(nil, home: "/Users/ana") == "—")
        #expect(ProcessFormat.directory("/opt", home: "") == "/opt")
    }

    @Test func startedIsAgo() {
        let now = Date(timeIntervalSince1970: 10_000)

        #expect(ProcessFormat.started(now.addingTimeInterval(-42 * 60), now: now, texts: es) == "hace 42 min")
        #expect(ProcessFormat.started(now.addingTimeInterval(-42 * 60), now: now, texts: en) == "42 min ago")
    }

    @Test func stopNotices() {
        #expect(
            ProcessFormat.notice(StopOutcome.requested, for: NoticeSubject(name: "node", closeKey: "⌘W"), texts: es)
                == "Se pidió a node que termine")
        #expect(
            ProcessFormat.notice(StopOutcome.confirming, for: NoticeSubject(name: "node", closeKey: "⌘W"), texts: es)
                == nil)
        #expect(
            ProcessFormat.notice(
                StopOutcome.protected(.paneShell), for: NoticeSubject(name: "zsh", closeKey: "⌘W"), texts: es)
                == "zsh es el shell del panel: ciérralo con ⌘W")
        #expect(
            ProcessFormat.notice(StopOutcome.failed(.gone), for: NoticeSubject(name: "node", closeKey: "⌘W"), texts: en)
                == "node no longer exists")
        #expect(
            ProcessFormat.notice(
                StopOutcome.failed(.refused(code: 1)), for: NoticeSubject(name: "node", closeKey: "⌘W"), texts: en)
                == "The system refused to act on node (error 1)")
        #expect(
            ProcessFormat.notice(StopOutcome.forced, for: NoticeSubject(name: "node", closeKey: "⌘W"), texts: es)
                == "Se forzó el cierre de node")
        #expect(
            ProcessFormat.notice(StopOutcome.waiting, for: NoticeSubject(name: "node", closeKey: "⌘W"), texts: en)
                == "Waiting for node to quit…")
        #expect(
            ProcessFormat.notice(
                StopOutcome.failed(.notYours), for: NoticeSubject(name: "x", closeKey: "⌘W"), texts: en)
                == "x isn’t yours: nothing was touched")
    }

    @Test func priorityNotices() {
        #expect(
            ProcessFormat.notice(
                PriorityOutcome.lowered(to: 5), for: NoticeSubject(name: "node", closeKey: "⌘W"), texts: es)
                == "node ahora tiene prioridad baja (5)")
        #expect(
            ProcessFormat.notice(
                PriorityOutcome.alreadyLowest, for: NoticeSubject(name: "node", closeKey: "⌘W"), texts: en)
                == "node already has the lowest priority")
        #expect(
            ProcessFormat.notice(
                PriorityOutcome.protected(.system), for: NoticeSubject(name: "Dock", closeKey: "⌘W"), texts: en)
                == "Can’t stop Dock: it is part of the system")
        #expect(
            ProcessFormat.notice(
                PriorityOutcome.failed(.gone), for: NoticeSubject(name: "x", closeKey: "⌘W"), texts: es)
                == "x ya no existe")
    }

    @Test func onlyRealFailuresAreErrors() {
        #expect(ProcessFormat.isFailure(.failed(.refused(code: 1))))
        #expect(ProcessFormat.isFailure(.failed(.notYours)))
        #expect(!ProcessFormat.isFailure(.failed(.gone)))
        #expect(!ProcessFormat.isFailure(.requested))
    }

    @Test func everyStateAndReasonHasWords() {
        for texts in [es, en] {
            for state in [ProcessState.active, .idle, .stopped, .unresponsive, .zombie] {
                #expect(!ProcessFormat.state(state, texts: texts).isEmpty)
            }
            for reason in ProtectionReason.allCases { #expect(texts.reasons[reason] != nil) }
        }
    }
}
