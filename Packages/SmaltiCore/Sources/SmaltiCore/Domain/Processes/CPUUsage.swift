/// CPU use per process between two samples: 100 is one core, as htop and Activity Monitor count it.
public enum CPUUsage {
    public static func percentages(previous: ProcessSample?, current: ProcessSample) -> [ProcessIdentity: Double] {
        guard let previous, current.takenAt > previous.takenAt else { return [:] }
        let wall = Double(current.takenAt - previous.takenAt)
        let before = Dictionary(previous.records.map { ($0.identity, $0.cpuTime) }) { first, _ in first }
        var usage: [ProcessIdentity: Double] = [:]
        for record in current.records {
            guard let earlier = before[record.identity] else { continue }
            let used = record.cpuTime >= earlier ? Double(record.cpuTime - earlier) : 0
            usage[record.identity] = used * 100 / wall
        }
        return usage
    }
}
