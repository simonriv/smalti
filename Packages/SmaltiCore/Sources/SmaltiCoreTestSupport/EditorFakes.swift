import Foundation
import SmaltiCore

public struct EditorBridgeCall: Equatable, Sendable {
    public let target: EditorTarget
    public let socket: String

    public init(target: EditorTarget, socket: String) {
        self.target = target
        self.socket = socket
    }
}

/// Records what it was asked to open; sockets in `unreachable` fail like a Neovim that is gone.
@MainActor
public final class FakeEditorBridge: EditorBridge {
    public var opened: [EditorBridgeCall] = []
    public var unreachable: Set<String> = []
    public var positions: [String: EditorPosition] = [:]

    public init() {}

    public func open(_ target: EditorTarget, socket: String) async throws(EditorError) {
        guard !unreachable.contains(socket) else { throw .unreachable(socket: socket, reason: "fake") }
        opened.append(EditorBridgeCall(target: target, socket: socket))
    }

    public func current(socket: String) async -> EditorPosition? { positions[socket] }
}

@MainActor
public final class FakeEditorPanes: EditorPanes {
    private let list: [(pane: PaneID, socket: String)]

    public init(editors: [(PaneID, String)]) {
        self.list = editors.map { (pane: $0.0, socket: $0.1) }
    }

    public func editors(near pane: PaneID) -> [(pane: PaneID, socket: String)] { list }
}
