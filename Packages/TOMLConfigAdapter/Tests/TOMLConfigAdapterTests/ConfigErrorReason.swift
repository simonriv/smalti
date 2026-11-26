import SmaltiCore

/// F7.7: the reason the Spanish interface shows, so these tests keep pinning the exact words they always did.
extension ConfigError {
    var reason: String { ConfigTexts.spanish.describe(problem) }
}
