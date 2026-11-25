/// `terraform`, `tofu` or `terragrunt` with `destroy` or `apply` among its first two subcommands
/// (`terragrunt run-all apply`). The environment cannot be read from the command: production.
struct TerraformRule: DestructiveCommandRule {
    private static let programs: Set<String> = ["terraform", "tofu", "terragrunt"]

    func finding(for command: SimpleCommand, context: GuardContext) -> GuardFinding? {
        guard let program = command.program, Self.programs.contains(program) else { return nil }
        let words = DestructiveCommandRules.positional(command.arguments).prefix(2)
        guard let verb = words.first(where: { $0 == "destroy" || $0 == "apply" }) else { return nil }
        return GuardFinding(rule: "\(program) \(verb)", environment: .undetermined)
    }
}

/// `railway … delete` and `railway down`.
struct RailwayRule: DestructiveCommandRule {
    func finding(for command: SimpleCommand, context: GuardContext) -> GuardFinding? {
        guard command.program == "railway" else { return nil }
        let words = DestructiveCommandRules.positional(command.arguments)
        guard let verb = words.firstIndex(where: { $0 == "delete" || $0 == "down" }) else { return nil }
        return GuardFinding(
            rule: (["railway"] + words[...verb]).joined(separator: " "), environment: .undetermined)
    }
}
