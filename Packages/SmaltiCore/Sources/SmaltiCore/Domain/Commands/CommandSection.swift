/// One group of palette results, in display order.
public struct CommandSection: Equatable, Sendable {
    public let group: CommandGroup
    public let commands: [RankedCommand]

    /// Groups in the order of their best result, rows by rank inside each group (Paleta.dc.html with "layout").
    /// Flattening the sections gives the order on screen, which keyboard selection follows.
    public static func grouping(_ ranked: [RankedCommand]) -> [CommandSection] {
        var order: [CommandGroup] = []
        for result in ranked where !order.contains(result.command.group) { order.append(result.command.group) }
        return order.map { group in
            CommandSection(group: group, commands: ranked.filter { $0.command.group == group })
        }
    }
}
