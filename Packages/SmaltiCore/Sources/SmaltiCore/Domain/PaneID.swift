import Foundation

/// Opaque identity of a terminal pane, stable for the pane's lifetime.
public struct PaneID: Hashable, Sendable, CustomStringConvertible {
    public let rawValue: UUID

    public init() {
        self.init(rawValue: UUID())
    }

    public init(rawValue: UUID) {
        self.rawValue = rawValue
    }

    public var description: String { rawValue.uuidString }
}
