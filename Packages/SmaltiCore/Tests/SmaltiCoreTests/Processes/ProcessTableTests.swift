import SmaltiCore
import Testing

@Suite("ProcessTable")
struct ProcessTableTests {
    private typealias F = ProcessFixtures
    private let web = PaneID()

    /// login (root, tty 7) → zsh 102 → npm 103 → node 104 (vite); zsh → python 105; a lone node 300 and postgres 400.
    private var records: [ProcessRecord] {
        [
            F.record(101, parent: 1, name: "login", isOwn: false, terminal: 7),
            F.record(102, parent: 101, name: "zsh", terminal: 7, arguments: ["-zsh"], memory: 6),
            F.record(103, parent: 102, name: "npm", terminal: 7, arguments: ["npm", "run", "dev"], memory: 58),
            F.record(
                104, parent: 103, name: "node", terminal: 7, arguments: ["node", "vite", "--port", "5173"],
                directory: "/Users/ana/dev/acme/web", memory: 412),
            F.record(
                105, parent: 102, name: "python3", terminal: 7, arguments: ["python3", "-m", "http.server"], memory: 22),
            F.record(300, parent: 1, name: "node", arguments: ["node", "watch.mjs"], memory: 41),
            F.record(400, parent: 1, name: "postgres", directory: "/opt/homebrew/var/postgres", memory: 40),
        ]
    }

    private var cpu: [ProcessIdentity: Double] {
        [
            id(102): 0, id(103): 0.1, id(104): 14.2, id(105): 0, id(300): 3.4, id(400): 1.2,
        ]
    }

    private func id(_ pid: Int32) -> ProcessIdentity { ProcessIdentity(pid: pid, startedAt: F.start) }

    private func rows(
        filter: String = "", order: ProcessOrder = .cpu, tree: Bool = false,
        phases: [ProcessIdentity: StopPhase] = [:], cpu: [ProcessIdentity: Double]? = nil
    ) -> [ProcessRow] {
        let attribution = PaneAttribution(records: records, foregroundGroups: [web: 104])
        let input = ProcessTableInput(
            sample: F.sample(records), cpu: cpu ?? self.cpu, attribution: attribution,
            policy: StopPolicy(ownPID: 9999), paneNames: [web: "web · 2"], phases: phases)
        return ProcessTable.rows(input, query: ProcessQuery(filter: filter, order: order, isTree: tree))
    }

    @Test func onlyOwnProcessesAreRows() {
        #expect(!rows().map(\.pid).contains(101))
        #expect(rows().count == 6)
    }

    @Test func flatOrderByCPUPutsBusiestFirstAndTiesByPID() {
        #expect(rows().map(\.pid) == [104, 300, 400, 103, 102, 105])
    }

    @Test func unknownCPUGoesLast() {
        var partial = cpu
        partial[id(104)] = nil

        #expect(rows(cpu: partial).last?.pid == 104)
    }

    @Test func orderByMemoryAndNameAndPID() {
        #expect(rows(order: .memory).map(\.pid) == [104, 103, 300, 400, 105, 102])
        #expect(rows(order: .name).map(\.pid) == [104, 300, 103, 400, 105, 102])
        #expect(rows(order: .pid).map(\.pid) == [102, 103, 104, 105, 300, 400])
    }

    @Test func ordersCycle() {
        #expect(ProcessOrder.cpu.next == .memory)
        #expect(ProcessOrder.pid.next == .cpu)
        #expect(PortOrder.port.next == .process)
        #expect(PortOrder.pane.next == .port)
    }

    /// Mutation 1: outside the tree nothing is dimmed as context.
    @Test func flatRowsAreNeverContext() {
        #expect(rows().allSatisfy { !$0.isContext })
        #expect(rows(filter: "vite").allSatisfy { !$0.isContext })
    }

    @Test func treeNestsChildrenUnderParentsWithGuides() {
        let tree = rows(tree: true)

        #expect(tree.map(\.pid) == [300, 400, 102, 103, 104, 105])
        #expect(tree.map(\.treePrefix) == ["", "", "", "├─ ", "│  └─ ", "└─ "])
        #expect(tree.map(\.depth) == [0, 0, 0, 1, 2, 1])
    }

    @Test func rowsCarryPaneCommandAndVerdict() throws {
        let node = try #require(rows().first { $0.pid == 104 })
        let shell = try #require(rows().first { $0.pid == 102 })

        #expect(node.pane == web)
        #expect(node.command == "node vite --port 5173")
        #expect(node.verdict == .allowed)
        #expect(shell.verdict == .protected(.paneShell))
        #expect(rows().first { $0.pid == 400 }?.pane == nil)
    }

    @Test func commandFallsBackToTheName() {
        #expect(rows().first { $0.pid == 400 }?.command == "postgres")
    }

    @Test func filterMatchesEveryWordIgnoringCaseAndAccents() {
        #expect(rows(filter: "NODE vite").map(\.pid) == [104])
        #expect(rows(filter: "pýthon").map(\.pid) == [105])
    }

    @Test func filterMatchesPIDDirectoryAndPane() {
        #expect(rows(filter: "300").map(\.pid) == [300])
        #expect(rows(filter: "homebrew").map(\.pid) == [400])
        #expect(Set(rows(filter: "web · 2").map(\.pid)) == [102, 103, 104, 105])
    }

    @Test func filterWithNoMatchIsEmpty() {
        #expect(rows(filter: "zzz").isEmpty)
    }

    @Test func treeFilterKeepsAncestorsAsContext() {
        let tree = rows(filter: "vite", tree: true)

        #expect(tree.map(\.pid) == [102, 103, 104])
        #expect(tree.map(\.isContext) == [true, true, false])
        #expect(tree.map(\.treePrefix) == ["", "└─ ", "   └─ "])
    }

    @Test func stateFollowsCPURunAndStopPhase() {
        let states = Dictionary(uniqueKeysWithValues: rows(phases: [id(300): .unresponsive]).map { ($0.pid, $0.state) })

        #expect(states[104] == .active)
        #expect(states[103] == .idle)
        #expect(states[300] == .unresponsive)
    }

    @Test(arguments: [
        (RunState.zombie, Double?.some(5), StopPhase?.none, ProcessState.zombie),
        (.stopped, 0, nil, .stopped),
        (.running, 0.5, nil, .active),
        (.running, 0.49, nil, .idle),
        (.sleeping, nil, nil, .idle),
        (.running, 9, .confirming, .unresponsive),
        (.running, 9, .requested(at: 0), .active),
    ])
    func stateOf(run: RunState, cpu: Double?, phase: StopPhase?, state: ProcessState) {
        #expect(ProcessState.of(run: run, cpu: cpu, phase: phase) == state)
    }

    /// The row's command: the program's name and what follows it, never a long argv[0] path.
    @Test func shortCommandIsTheNameAndTheArguments() {
        let python = F.record(
            9, name: "Python", executable: "/Applications/Xcode.app/Contents/MacOS/Python",
            arguments: ["/Applications/Xcode.app/Contents/MacOS/Python", "server.py"])

        #expect(python.shortCommand == "Python server.py")
        #expect(F.record(9, name: "zsh", arguments: ["-zsh"]).shortCommand == "-zsh")
        #expect(F.record(9, name: "postgres").shortCommand == "postgres")
    }

    @Test func displayNameComesFromTheExecutable() {
        let record = F.record(
            9, name: "ControlCe",
            executable: "/System/Library/CoreServices/ControlCenter.app/Contents/MacOS/ControlCenter")

        #expect(record.displayName == "ControlCenter")
        #expect(F.record(9, name: "zsh").displayName == "zsh")
    }
}
