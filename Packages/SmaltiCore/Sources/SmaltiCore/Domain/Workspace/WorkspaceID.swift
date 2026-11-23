import Foundation

/// Opaque identity of a workspace, stable for its lifetime.
public struct WorkspaceID: Hashable, Sendable, CustomStringConvertible {
    public let rawValue: UUID

    public init() {
        self.init(rawValue: UUID())
    }

    public init(rawValue: UUID) {
        self.rawValue = rawValue
    }

    public var description: String { rawValue.uuidString }
}
