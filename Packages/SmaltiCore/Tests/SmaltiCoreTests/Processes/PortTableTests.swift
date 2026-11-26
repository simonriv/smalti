import SmaltiCore
import Testing

@Suite("PortTable")
struct PortTableTests {
    private typealias F = ProcessFixtures
    private let web = PaneID()

    private var records: [ProcessRecord] {
        [
            F.record(101, parent: 1, name: "login", isOwn: false, terminal: 7),
            F.record(102, parent: 101, name: "zsh", terminal: 7),
            F.record(104, parent: 102, name: "node", terminal: 7, arguments: ["node", "vite"], directory: "/w"),
            F.record(400, parent: 1, name: "postgres"),
            F.record(500, parent: 1, name: "next"),
        ]
    }

    private var sockets: [ListeningSocket] {
        [
            ListeningSocket(pid: 104, transport: .tcp, port: 5173, address: "127.0.0.1"),
            ListeningSocket(pid: 104, transport: .tcp, port: 5173, address: "::1"),
            ListeningSocket(pid: 400, transport: .tcp, port: 5432, address: "127.0.0.1"),
            ListeningSocket(pid: 500, transport: .tcp, port: 3000, address: "::"),
            ListeningSocket(pid: 500, transport: .udp, port: 3000, address: "127.0.0.1"),
            ListeningSocket(pid: 777, transport: .tcp, port: 9000, address: "10.0.0.2"),
        ]
    }

    private func rows(filter: String = "", order: PortOrder = .port) -> [PortRow] {
        let attribution = PaneAttribution(records: records, foregroundGroups: [web: 104])
        let input = ProcessTableInput(
            sample: F.sample(records), cpu: [:], attribution: attribution, policy: StopPolicy(ownPID: 1),
            paneNames: [web: "web · 2"], phases: [:])
        let processes = ProcessTable.rowsByPID(input)
        return PortTable.rows(
            sockets: sockets, context: PortContext(processes: processes, paneNames: input.paneNames),
            query: PortQuery(filter: filter, order: order))
    }

    @Test func groupsAddressesOfTheSameListener() throws {
        let vite = try #require(rows().first { $0.port == 5173 })

        #expect(rows().count == 5)
        #expect(vite.addresses == ["127.0.0.1", "::1"])
        #expect(vite.scope == .local)
        #expect(vite.process?.pane == web)
    }

    @Test func wildcardAndConcreteScopes() {
        #expect(rows().first { $0.port == 3000 && $0.transport == .tcp }?.scope == .all)
        #expect(rows().first { $0.port == 9000 }?.scope == .specific(["10.0.0.2"]))
    }

    @Test func orderByPortThenTransport() {
        #expect(
            rows().map { "\($0.port)/\($0.transport.rawValue)" } == [
                "3000/TCP", "3000/UDP", "5173/TCP", "5432/TCP", "9000/TCP",
            ])
    }

    @Test func orderByProcessPutsUnknownLast() {
        #expect(rows(order: .process).map(\.port) == [3000, 3000, 5173, 5432, 9000])
    }

    /// Mutation 1: by process name even when the ports say otherwise, and a listener without a process last even on
    /// a lower port.
    @Test func orderByProcessFollowsNamesNotPorts() throws {
        let alpha = F.record(10, name: "alpha")
        let beta = F.record(11, name: "beta")
        let input = ProcessTableInput(
            sample: F.sample([alpha, beta]), cpu: [:],
            attribution: PaneAttribution(records: [alpha, beta], foregroundGroups: [:]), policy: StopPolicy(ownPID: 1),
            paneNames: [:], phases: [:])
        let sockets = [
            ListeningSocket(pid: 99, transport: .tcp, port: 1000, address: "127.0.0.1"),
            ListeningSocket(pid: 11, transport: .tcp, port: 3000, address: "127.0.0.1"),
            ListeningSocket(pid: 10, transport: .tcp, port: 9000, address: "127.0.0.1"),
        ]

        let rows = PortTable.rows(
            sockets: sockets, context: PortContext(processes: ProcessTable.rowsByPID(input), paneNames: [:]),
            query: PortQuery(filter: "", order: .process))

        #expect(rows.map(\.pid) == [10, 11, 99])
    }

    @Test func orderByPanePutsPanelessLast() {
        #expect(rows(order: .pane).first?.port == 5173)
    }

    @Test func filterByPortNumberAndProcess() {
        #expect(rows(filter: "5432").map(\.port) == [5432])
        #expect(rows(filter: "vite").map(\.port) == [5173])
        #expect(rows(filter: "udp").map(\.transport) == [.udp])
        #expect(rows(filter: "web · 2").map(\.port) == [5173])
    }

    @Test func summaryCountsOpenToNetwork() {
        let summary = PortTable.summary(rows())

        #expect(summary.total == 5)
        #expect(summary.openToNetwork == 2)
    }

    @Test func noSocketsNoRows() {
        #expect(
            PortTable.rows(
                sockets: [], context: PortContext(processes: [:], paneNames: [:]),
                query: PortQuery(filter: "", order: .port)
            )
            .isEmpty)
    }
}
