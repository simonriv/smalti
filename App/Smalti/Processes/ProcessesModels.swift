import Foundation
import SmaltiCore

/// What the processes view paints, already in words: the controller builds it from the domain's tables, the views
/// only lay it out (no rules here either).
enum ProcessesCell: Equatable {
    case state(ProcessState)
    /// Tree guides, the name, the command after it, an optional "protegido" tag and an amber hint.
    case process(ProcessCellContent)
    case text(String, ProcessesTextStyle)
    case cpu(Double?)
}

struct ProcessCellContent: Equatable {
    let prefix: String
    let name: String
    let detail: String
    let tag: String?
    let hint: String?
    /// The ports view shows the state as a dot before the name.
    let dot: ProcessState?
    let isContext: Bool
}

enum ProcessesTextStyle: Equatable {
    case title, primary, secondary, mono, monoSecondary, monoTitle
}

struct ProcessesRowModel: Equatable {
    let id: String
    let cells: [ProcessesCell]
    let accessibilityIdentifier: String
    let accessibilityLabel: String
}

struct ProcessesDetailModel: Equatable {
    struct Fact: Equatable {
        let key: String
        let value: String
        var isMono = false
    }

    struct Action: Equatable {
        let keys: String
        let title: String
    }

    let caption: String
    let command: String?
    let state: ProcessState?
    let facts: [Fact]
    let actions: [Action]
    /// Why nothing can be done to it, instead of the actions.
    let protection: String?
}

struct ProcessesTotalsModel: Equatable {
    let caption: String
    let cpu: String
    let cpuHistory: [Double]
    let memory: String
    let panesFraction: Double
    let restFraction: Double
    let memoryNote: String
    let footnote: String
}

struct PortsSummaryModel: Equatable {
    let total: String
    let openToNetwork: String
    let footnote: String
}

struct ProcessesScreen: Equatable {
    enum Side: Equatable {
        case totals(ProcessesTotalsModel)
        case summary(PortsSummaryModel)
    }

    let mode: ProcessesController.Mode
    let headers: [String]
    let columns: [Double?]
    let rows: [ProcessesRowModel]
    let selected: String?
    let empty: String?
    let detail: ProcessesDetailModel?
    let side: Side
    let order: String
    let isTree: Bool
}
