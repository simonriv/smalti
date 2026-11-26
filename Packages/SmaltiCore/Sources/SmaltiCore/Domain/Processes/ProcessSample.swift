/// Every process at one moment.
public struct ProcessSample: Equatable, Sendable {
    public let records: [ProcessRecord]
    /// Monotonic clock, in nanoseconds: only differences between samples mean something.
    public let takenAt: UInt64
    /// Processes of other users or of the system, which cannot be read without privileges.
    public let hiddenCount: Int
    /// The machine's memory, in bytes.
    public let memoryTotal: UInt64

    public init(records: [ProcessRecord], takenAt: UInt64, hiddenCount: Int, memoryTotal: UInt64) {
        self.records = records
        self.takenAt = takenAt
        self.hiddenCount = hiddenCount
        self.memoryTotal = memoryTotal
    }
}
