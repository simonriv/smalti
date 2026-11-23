import Foundation
import SmaltiCore
import Testing

/// Every `TelemetrySource` delivers what is sent to it, in order.
public enum TelemetrySourceContract {
    @MainActor
    public static func verify(
        _ make: () -> (source: any TelemetrySource, send: (AgentEvent) async -> Void)
    ) async {
        let (source, send) = make()
        let pane = PaneID()
        let sent = [AgentHook.sessionStart, .stop].map {
            AgentEvent(
                pane: pane, hook: $0, at: Date(timeIntervalSince1970: 1_800_000_000),
                sessionID: "8f2c1a90-4d3e-4b7a-9c11-2f6e5d4c3b2a")
        }
        var iterator = source.events().makeAsyncIterator()
        for event in sent { await send(event) }
        var received: [AgentEvent] = []
        for _ in sent {
            if let event = await iterator.next() { received.append(event) }
        }
        #expect(received == sent, "events arrive as sent, in order")
    }
}

/// Every `Notifier` delivers each notice once, as given.
public enum NotifierContract {
    @MainActor
    public static func verify(_ make: () -> (notifier: any Notifier, delivered: () -> [AttentionNotice])) {
        let (notifier, delivered) = make()
        let notices = [
            AttentionNotice(pane: PaneID(), title: "rizaria/web", body: "pide permiso para `ls`"),
            AttentionNotice(pane: PaneID(), title: "solen/api", body: "terminó y te espera"),
        ]
        notices.forEach(notifier.notify)
        #expect(delivered() == notices, "each notice is delivered once, in order")
    }
}

/// Every `HarnessIntegration` reports what install and uninstall did.
public enum HarnessIntegrationContract {
    @MainActor
    public static func verify(_ integration: some HarnessIntegration) async {
        try? await integration.install()
        #expect(await integration.isInstalled, "installed after install")
        try? await integration.uninstall()
        #expect(await !integration.isInstalled, "not installed after uninstall")
    }
}
