import Foundation
import SmaltiCore

/// Turns the domain's tables into what the processes view paints, in the interface's language. No rules: what is
/// shown, sorted, protected or stoppable comes from `ProcessTable`, `PortTable` and `StopPolicy`.
@MainActor
struct ProcessesPresenter {
    struct State {
        let mode: ProcessesController.Mode
        let filter: String
        let processOrder: ProcessOrder
        let portOrder: PortOrder
        let isTree: Bool
        let selection: String?
        let cpuHistory: [Double]
    }

    /// The rows behind the screen, for the controller's actions.
    struct Output {
        let screen: ProcessesScreen
        let processes: [String: ProcessRow]
        let panes: [String: PaneID]
    }

    let texts: ProcessTexts
    let tokens: ProcessesTokens
    let home: String
    let keymap: Keymap
    let now: Date

    func make(_ snapshot: ProcessesSnapshot, input: ProcessTableInput, state: State) -> Output {
        switch state.mode {
        case .processes: processes(snapshot, input: input, state: state)
        case .ports: ports(snapshot, input: input, state: state)
        }
    }

    // MARK: - Processes

    private func processes(_ snapshot: ProcessesSnapshot, input: ProcessTableInput, state: State) -> Output {
        let rows = ProcessTable.rows(
            input, query: ProcessQuery(filter: state.filter, order: state.processOrder, isTree: state.isTree))
        let ids = rows.map { Self.id(of: $0) }
        let selected = ids.contains(state.selection ?? "") ? state.selection : ids.first
        let chosen = rows.first { Self.id(of: $0) == selected }
        let screen = ProcessesScreen(
            mode: .processes, headers: processHeaders(state.processOrder),
            columns: tokens.processColumns, rows: rows.map { processRow($0, input) },
            selected: selected,
            empty: rows.isEmpty
                ? (state.filter.isEmpty ? texts.noProcesses : texts.noMatch(["filter": state.filter])) : nil,
            detail: chosen.map { processDetail($0, input: input, snapshot: snapshot) },
            side: .totals(totals(snapshot, history: state.cpuHistory)), order: orderTitle(state.processOrder),
            isTree: state.isTree)
        return Output(
            screen: screen, processes: Dictionary(uniqueKeysWithValues: zip(ids, rows)),
            panes: Dictionary(uniqueKeysWithValues: zip(ids, rows).compactMap { id, row in row.pane.map { (id, $0) } }))
    }

    static func id(of row: ProcessRow) -> String { "p\(row.pid)" }

    private func processHeaders(_ order: ProcessOrder) -> [String] {
        var headers = [
            String(localized: "Status"), String(localized: "Process"), String(localized: "Pane"), "CPU",
            String(localized: "Memory"), "PID",
        ]
        let (index, arrow) =
            switch order {
            case .cpu: (3, "↓")
            case .memory: (4, "↓")
            case .name: (1, "↑")
            case .pid: (5, "↑")
            }
        headers[index] += " " + arrow
        return headers
    }

    private func orderTitle(_ order: ProcessOrder) -> String {
        switch order {
        case .cpu: "CPU ↓"
        case .memory: String(localized: "Memory ↓")
        case .name: String(localized: "Name ↑")
        case .pid: "PID ↑"
        }
    }

    private func processRow(_ row: ProcessRow, _ input: ProcessTableInput) -> ProcessesRowModel {
        let pane = row.pane.flatMap { input.paneNames[$0] }
        let content = ProcessCellContent(
            prefix: row.treePrefix, name: row.name,
            detail: Self.arguments(row).isEmpty ? row.command : Self.arguments(row), tag: tag(row.verdict),
            hint: row.state == .unresponsive ? texts.unresponsiveHint : nil, dot: nil, isContext: row.isContext)
        return ProcessesRowModel(
            id: Self.id(of: row),
            cells: [
                .state(row.state), .process(content), .text(pane ?? "—", pane == nil ? .secondary : .primary),
                .cpu(row.cpu), .text(ProcessFormat.memory(row.record.memory), .mono),
                .text(String(row.pid), .monoSecondary),
            ],
            accessibilityIdentifier: "smalti.processes.row.\(row.pid)",
            accessibilityLabel: [
                ProcessFormat.state(row.state, texts: texts), row.name, pane ?? "", ProcessFormat.cpu(row.cpu),
                ProcessFormat.memory(row.record.memory),
            ].filter { !$0.isEmpty }.joined(separator: " · "))
    }

    private func tag(_ verdict: StopVerdict) -> String? {
        verdict.isAllowed ? nil : texts.protected
    }

    private func processDetail(
        _ row: ProcessRow, input: ProcessTableInput, snapshot: ProcessesSnapshot
    ) -> ProcessesDetailModel {
        let pane = row.pane.flatMap { input.paneNames[$0] }
        let parent = input.sample.records.first { $0.pid == row.record.parent && $0.isOwn }
        let listens = snapshot.sockets.filter { $0.pid == row.pid }.map {
            "\(Self.hostPort($0.address, $0.port)) \($0.transport.rawValue)"
        }
        var facts = [
            fact(
                String(localized: "Directory"), ProcessFormat.directory(row.record.workingDirectory, home: home),
                mono: true),
            fact(String(localized: "Pane"), pane.map { "\($0) · ↵ \(String(localized: "go"))" } ?? "—"),
        ]
        if let parent { facts.append(fact(String(localized: "Parent"), "\(parent.displayName) \(parent.pid)")) }
        facts.append(
            fact(String(localized: "Started"), ProcessFormat.started(row.identity.startedAt, now: now, texts: texts)))
        if !listens.isEmpty {
            facts.append(fact(String(localized: "Listens"), listens.joined(separator: ", "), mono: true))
        }
        facts.append(fact(String(localized: "Priority"), ProcessFormat.priority(row.record.nice, texts: texts)))
        facts.append(fact(String(localized: "Threads"), String(row.record.threads), mono: true))
        var actions = [
            ProcessesDetailModel.Action(keys: chord(.processesStop), title: String(localized: "Stop")),
            ProcessesDetailModel.Action(
                keys: chord(.processesLowerPriority), title: String(localized: "Lower Priority")),
        ]
        if let pane { actions.append(.init(keys: "↵", title: texts.goToPane(["pane": pane]))) }
        return ProcessesDetailModel(
            caption: String(localized: "Process · \(row.name)"), command: row.command, state: row.state, facts: facts,
            actions: actions, protection: protection(row))
    }

    private func protection(_ row: ProcessRow) -> String? {
        guard case .protected(let reason) = row.verdict else { return nil }
        return ProcessFormat.notice(
            StopOutcome.protected(reason), for: NoticeSubject(name: row.name, closeKey: chord(.paneClose)), texts: texts
        )
    }

    // MARK: - Ports

    private func ports(_ snapshot: ProcessesSnapshot, input: ProcessTableInput, state: State) -> Output {
        let processes = ProcessTable.rowsByPID(input)
        let rows = PortTable.rows(
            sockets: snapshot.sockets, context: PortContext(processes: processes, paneNames: input.paneNames),
            query: PortQuery(filter: state.filter, order: state.portOrder))
        let ids = rows.map(Self.id(of:))
        let selected = ids.contains(state.selection ?? "") ? state.selection : ids.first
        let chosen = rows.first { Self.id(of: $0) == selected }
        let summary = PortTable.summary(rows)
        let screen = ProcessesScreen(
            mode: .ports, headers: portHeaders(state.portOrder), columns: tokens.portColumns,
            rows: rows.map { portRow($0, input) }, selected: selected,
            empty: rows.isEmpty
                ? (state.filter.isEmpty ? texts.noPorts : texts.noMatch(["filter": state.filter])) : nil,
            detail: chosen.map { portDetail($0, input: input) },
            side: .summary(
                PortsSummaryModel(
                    total: texts.ports(summary.total), openToNetwork: texts.openToNetwork(summary.openToNetwork),
                    footnote: String(
                        localized:
                            "“All” means other computers on your network can connect. The list is lsof’s (TCP in LISTEN and unconnected UDP), only for your processes."
                    ))),
            order: portOrderTitle(state.portOrder), isTree: false)
        let pairs = zip(ids, rows)
        return Output(
            screen: screen,
            processes: Dictionary(uniqueKeysWithValues: pairs.compactMap { id, row in row.process.map { (id, $0) } }),
            panes: Dictionary(uniqueKeysWithValues: pairs.compactMap { id, row in row.process?.pane.map { (id, $0) } }))
    }

    static func id(of row: PortRow) -> String {
        "\(row.pid).\(row.transport.rawValue.lowercased()).\(row.port)"
    }

    private func portHeaders(_ order: PortOrder) -> [String] {
        var headers = [
            String(localized: "Port"), String(localized: "Protocol"), String(localized: "Address"),
            String(localized: "Process"), "PID", String(localized: "Directory"), String(localized: "Pane"),
        ]
        let index =
            switch order {
            case .port: 0
            case .process: 3
            case .pane: 6
            }
        headers[index] += " ↑"
        return headers
    }

    private func portOrderTitle(_ order: PortOrder) -> String {
        switch order {
        case .port: String(localized: "Port ↑")
        case .process: String(localized: "Process ↑")
        case .pane: String(localized: "Pane ↑")
        }
    }

    private func portRow(_ row: PortRow, _ input: ProcessTableInput) -> ProcessesRowModel {
        let process = row.process
        let pane = process?.pane.flatMap { input.paneNames[$0] }
        let content = ProcessCellContent(
            prefix: "", name: process?.name ?? "—", detail: process.map { Self.arguments($0) } ?? "",
            tag: process.flatMap { tag($0.verdict) }, hint: nil, dot: process?.state, isContext: false)
        let scope = ProcessFormat.scope(row.scope, texts: texts)
        return ProcessesRowModel(
            id: Self.id(of: row),
            cells: [
                .text(String(row.port), .monoTitle), .text(row.transport.rawValue, .monoSecondary),
                .text(scope, row.scope == .local ? .secondary : .title), .process(content),
                .text(String(row.pid), .monoSecondary),
                .text(ProcessFormat.directory(process?.record.workingDirectory, home: home), .mono),
                .text(pane ?? "—", pane == nil ? .secondary : .primary),
            ],
            accessibilityIdentifier: "smalti.ports.row.\(Self.id(of: row))",
            accessibilityLabel: [
                String(row.port), row.transport.rawValue, scope,
                process.map { ProcessFormat.state($0.state, texts: texts) } ?? "",
                process?.name ?? "", pane ?? "",
            ]
            .filter { !$0.isEmpty }.joined(separator: " · "))
    }

    /// What follows the program's own name: `vite --port 5173` for `node vite --port 5173`.
    private static func arguments(_ row: ProcessRow) -> String {
        row.record.arguments.dropFirst().joined(separator: " ")
    }

    private func portDetail(_ row: PortRow, input: ProcessTableInput) -> ProcessesDetailModel {
        let caption = String(localized: "Port \(String(row.port)) · \(row.transport.rawValue)")
        let bound = texts.listensOn([
            "addresses": row.addresses.joined(separator: ", "), "scope": ProcessFormat.scope(row.scope, texts: texts),
        ])
        guard let process = row.process else {
            return ProcessesDetailModel(
                caption: caption, command: nil, state: nil,
                facts: [fact(String(localized: "Listens on"), bound), fact("PID", String(row.pid), mono: true)],
                actions: [], protection: nil)
        }
        let pane = process.pane.flatMap { input.paneNames[$0] }
        let facts = [
            fact(String(localized: "Listens on"), bound),
            fact(String(localized: "Process"), "\(process.name) \(process.pid)"),
            fact(
                String(localized: "Command"),
                Self.arguments(process).isEmpty ? process.command : Self.arguments(process), mono: true),
            fact(
                String(localized: "Directory"), ProcessFormat.directory(process.record.workingDirectory, home: home),
                mono: true),
            fact(String(localized: "Pane"), pane.map { "\($0) · ↵ \(String(localized: "go"))" } ?? "—"),
            fact(
                String(localized: "Started"), ProcessFormat.started(process.identity.startedAt, now: now, texts: texts)),
        ]
        var actions = [
            ProcessesDetailModel.Action(
                keys: chord(.processesStop), title: texts.stopNamed(["name": process.name, "pid": String(process.pid)]))
        ]
        if let pane { actions.append(.init(keys: "↵", title: texts.goToPane(["pane": pane]))) }
        return ProcessesDetailModel(
            caption: caption, command: nil, state: process.state, facts: facts, actions: actions,
            protection: protection(process))
    }

    // MARK: - Cards

    private func totals(_ snapshot: ProcessesSnapshot, history: [Double]) -> ProcessesTotalsModel {
        let totals = snapshot.totals
        let total = Double(max(totals.memoryTotal, 1))
        let rest = totals.memory > totals.paneMemory ? totals.memory - totals.paneMemory : 0
        return ProcessesTotalsModel(
            caption: String(localized: "Your processes · \(totals.count)"),
            cpu: totals.cpu.map { "\(Int($0.rounded()))%" } ?? "—", cpuHistory: history,
            memory: ObservatoryFormat.memory(used: totals.memory, total: totals.memoryTotal),
            panesFraction: Double(totals.paneMemory) / total, restFraction: Double(rest) / total,
            memoryNote: texts.panesSplit([
                "panes": ObservatoryFormat.gigabytes(totals.paneMemory), "rest": ObservatoryFormat.gigabytes(rest),
            ]),
            footnote: texts.hiddenNote([
                "hidden": String(totals.hidden),
                "seconds": String(ProcessesRefresher.Timing.standard.every.components.seconds),
            ]))
    }

    // MARK: - Helpers

    private func fact(_ key: String, _ value: String, mono: Bool = false) -> ProcessesDetailModel.Fact {
        ProcessesDetailModel.Fact(key: key, value: value, isMono: mono)
    }

    private func chord(_ command: CommandID) -> String {
        keymap.chord(for: command)?.display ?? ""
    }

    /// `127.0.0.1:5173`, `[::1]:5173`.
    private static func hostPort(_ address: String, _ port: UInt16) -> String {
        address.contains(":") ? "[\(address)]:\(port)" : "\(address):\(port)"
    }
}
