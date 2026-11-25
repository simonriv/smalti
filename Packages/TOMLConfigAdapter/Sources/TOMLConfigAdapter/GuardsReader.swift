import SmaltiCore

/// `[guards]` (spec F7.5): `production_hosts`, `non_production_hosts` and `provider_api_hosts`, lists of host
/// names where `*` stands for one or more labels. An unwritten key keeps its default (empty).
enum GuardsReader {
    static func read(_ section: TOMLSection) throws(ConfigError) -> GuardSettings {
        try section.rejectUnknownKeys(allowed: ["production_hosts", "non_production_hosts", "provider_api_hosts"])
        var settings = GuardSettings.standard
        settings.productionHosts = try section.texts("production_hosts") ?? settings.productionHosts
        settings.nonProductionHosts = try section.texts("non_production_hosts") ?? settings.nonProductionHosts
        settings.providerAPIHosts = try section.texts("provider_api_hosts") ?? settings.providerAPIHosts
        return settings
    }
}
