import Foundation

/// What the process view asks for.
public struct ProcessQuery: Equatable, Sendable {
    public let filter: String
    public let order: ProcessOrder
    public let isTree: Bool

    public init(filter: String, order: ProcessOrder, isTree: Bool) {
        self.filter = filter
        self.order = order
        self.isTree = isTree
    }
}

/// The facts both views are built from.
public struct ProcessTableInput: Sendable {
    public let sample: ProcessSample
    public let cpu: [ProcessIdentity: Double]
    public let attribution: PaneAttribution
    public let policy: StopPolicy
    /// "web · 2" for each pane, as the app names them.
    public let paneNames: [PaneID: String]
    public let phases: [ProcessIdentity: StopPhase]

    public init(
        sample: ProcessSample, cpu: [ProcessIdentity: Double], attribution: PaneAttribution, policy: StopPolicy,
        paneNames: [PaneID: String], phases: [ProcessIdentity: StopPhase]
    ) {
        self.sample = sample
        self.cpu = cpu
        self.attribution = attribution
        self.policy = policy
        self.paneNames = paneNames
        self.phases = phases
    }
}

/// One row of the process view.
public struct ProcessRow: Equatable, Sendable {
    public let record: ProcessRecord
    public let pane: PaneID?
    public let cpu: Double?
    public let state: ProcessState
    public let verdict: StopVerdict
    /// Tree guides before the name (`├─ `, `│  └─ `); empty outside the tree.
    public let treePrefix: String
    public let depth: Int
    /// Shown dimmed in the tree: an ancestor of a match that does not match itself.
    public let isContext: Bool

    public var identity: ProcessIdentity { record.identity }
    public var pid: Int32 { record.pid }
    public var name: String { record.displayName }
    public var command: String { record.command }

    func placed(prefix: String, depth: Int, isContext: Bool) -> ProcessRow {
        ProcessRow(
            record: record, pane: pane, cpu: cpu, state: state, verdict: verdict, treePrefix: prefix, depth: depth,
            isContext: isContext)
    }
}

/// The process view: the person's own processes, filtered, sorted, flat or as a tree (spec F8, "La vista").
public enum ProcessTable {
    public static func rows(_ input: ProcessTableInput, query: ProcessQuery) -> [ProcessRow] {
        let all = baseRows(input)
        let filter = TextFilter(query.filter)
        let matching = Set(all.filter { filter.isEmpty || filter.matches(fields(of: $0, input.paneNames)) }.map(\.pid))
        let sorted = all.sorted(by: comparator(query.order))
        guard query.isTree else { return sorted.filter { matching.contains($0.pid) } }
        return ProcessTree(rows: sorted, matching: matching).flattened()
    }

    /// Every own process's row, unfiltered, by PID: what the port view shows for each listener.
    public static func rowsByPID(_ input: ProcessTableInput) -> [Int32: ProcessRow] {
        Dictionary(baseRows(input).map { ($0.pid, $0) }) { first, _ in first }
    }

    private static func baseRows(_ input: ProcessTableInput) -> [ProcessRow] {
        input.sample.records.filter(\.isOwn).map { record in
            let cpu = input.cpu[record.identity]
            return ProcessRow(
                record: record, pane: input.attribution.pane(of: record.pid), cpu: cpu,
                state: .of(run: record.run, cpu: cpu, phase: input.phases[record.identity]),
                verdict: input.policy.verdict(for: record, attribution: input.attribution), treePrefix: "",
                depth: 0, isContext: false)
        }
    }

    static func fields(of row: ProcessRow, _ paneNames: [PaneID: String]) -> [String] {
        [row.name, row.command, String(row.pid), row.record.workingDirectory ?? "", row.pane.flatMap { paneNames[$0] } ?? ""]
    }

    private static func comparator(_ order: ProcessOrder) -> (ProcessRow, ProcessRow) -> Bool {
        switch order {
        case .cpu: { ($0.cpu ?? -1, $1.pid) > ($1.cpu ?? -1, $0.pid) }
        case .memory: { ($0.record.memory, $1.pid) > ($1.record.memory, $0.pid) }
        case .name: { (folded($0.name), $0.pid) < (folded($1.name), $1.pid) }
        case .pid: { $0.pid < $1.pid }
        }
    }

    static func folded(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }
}

/// Nests already sorted rows under their parents, keeping only matches and their ancestors.
private struct ProcessTree {
    private let rows: [ProcessRow]
    private let visible: Set<Int32>
    private let matching: Set<Int32>
    private let children: [Int32: [ProcessRow]]

    init(rows: [ProcessRow], matching: Set<Int32>) {
        let byPID = Dictionary(rows.map { ($0.pid, $0) }) { first, _ in first }
        var visible: Set<Int32> = []
        for pid in matching {
            var current = byPID[pid]
            while let row = current, visible.insert(row.pid).inserted { current = byPID[row.record.parent] }
        }
        self.rows = rows
        self.visible = visible
        self.matching = matching
        var children: [Int32: [ProcessRow]] = [:]
        for row in rows where visible.contains(row.pid) && visible.contains(row.record.parent) {
            children[row.record.parent, default: []].append(row)
        }
        self.children = children
    }

    func flattened() -> [ProcessRow] {
        let roots = rows.filter { visible.contains($0.pid) && !visible.contains($0.record.parent) }
        var result: [ProcessRow] = []
        var placed: Set<Int32> = []
        for root in roots { append(root, guides: "", isLast: nil, depth: 0, into: &result, placed: &placed) }
        return result
    }

    /// `isLast` is nil for a root; `guides` are the ancestors' columns (`│  ` or three spaces).
    private func append(
        _ row: ProcessRow, guides: String, isLast: Bool?, depth: Int, into result: inout [ProcessRow],
        placed: inout Set<Int32>
    ) {
        guard placed.insert(row.pid).inserted else { return }
        let prefix = isLast.map { guides + ($0 ? "└─ " : "├─ ") } ?? ""
        result.append(row.placed(prefix: prefix, depth: depth, isContext: !matching.contains(row.pid)))
        let below = children[row.pid] ?? []
        let nextGuides = isLast.map { guides + ($0 ? "   " : "│  ") } ?? ""
        for (index, child) in below.enumerated() {
            append(
                child, guides: nextGuides, isLast: index == below.count - 1, depth: depth + 1, into: &result,
                placed: &placed)
        }
    }
}
