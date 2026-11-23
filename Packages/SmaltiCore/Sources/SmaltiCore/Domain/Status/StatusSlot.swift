/// The one status line both kinds of message compete for. A persistent message (an invalid config) stays until it
/// is replaced or cleared; a transient one (a pane that does not fit) shows over it for a while and then gives the
/// line back, so a transient message never wipes a persistent one.
public struct StatusSlot<Message: Equatable & Sendable>: Equatable, Sendable {
    public private(set) var persistent: Message?
    public private(set) var transient: Message?

    public init() {}

    /// What the status line shows: the transient message over the persistent one.
    public var showing: Message? { transient ?? persistent }

    public func withTransient(_ message: Message) -> StatusSlot {
        var updated = self
        updated.transient = message
        return updated
    }

    /// Clears the transient message only while it is still `message`, so an older timer cannot clear a newer one.
    public func clearingTransient(_ message: Message) -> StatusSlot {
        guard transient == message else { return self }
        var updated = self
        updated.transient = nil
        return updated
    }

    /// Replaces (or with `nil` clears) the persistent message. Any transient one is dropped so the newest shows.
    public func withPersistent(_ message: Message?) -> StatusSlot {
        var updated = self
        updated.persistent = message
        updated.transient = nil
        return updated
    }
}
