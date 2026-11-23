import Foundation
import SmaltiCore

/// Busy and total CPU ticks, summed over every core.
struct CPUTicks: Equatable {
    let busy: UInt64
    let total: UInt64

    /// Percent of the elapsed ticks spent busy; nil when no time passed.
    static func usage(previous: CPUTicks, current: CPUTicks) -> Double? {
        guard current.total > previous.total, current.busy >= previous.busy else { return nil }
        return Double(current.busy - previous.busy) * 100 / Double(current.total - previous.total)
    }
}

struct MemoryPages: Equatable {
    let active: UInt64
    let wired: UInt64
    let compressed: UInt64
}

enum MemoryReader {
    /// Activity Monitor's "used": active, wired and compressed pages.
    static func used(_ pages: MemoryPages, pageSize: UInt64) -> UInt64 {
        (pages.active + pages.wired + pages.compressed) * pageSize
    }

    /// `kern.memorystatus_vm_pressure_level`: 1 normal, 2 warning, 4 critical.
    static func pressure(level: Int32) -> Reading<MemoryPressure> {
        guard let pressure = levels[level] else { return .unavailable }
        return .value(pressure)
    }

    private static let levels: [Int32: MemoryPressure] = [1: .normal, 2: .media, 4: .alta]
}

/// "MacBook Air M4": the product name without its details in parentheses, plus the chip.
enum MachineName {
    private static let chipPrefix = "Apple "

    static func display(productName: Data?, chip: String) -> String {
        let product = productName.flatMap { String(data: $0, encoding: .utf8) }?
            .trimmingCharacters(in: CharacterSet(charactersIn: "\0").union(.whitespaces))
        guard let product, !product.isEmpty else { return chip }
        let base = product.split(separator: "(", maxSplits: 1).first.map { $0.trimmingCharacters(in: .whitespaces) }
        let shortChip = chip.hasPrefix(chipPrefix) ? String(chip.dropFirst(chipPrefix.count)) : chip
        return [base ?? product, shortChip].filter { !$0.isEmpty }.joined(separator: " ")
    }
}
