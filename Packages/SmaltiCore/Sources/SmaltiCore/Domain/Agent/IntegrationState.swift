/// Whether Smalti's integration is installed in a harness. `unknown` covers "not asked yet", a missing harness and a
/// failing check: the palette then offers neither install nor uninstall (spec F5.6).
public enum IntegrationState: Equatable, Sendable {
    case installed
    case notInstalled
    /// F7.5: installed, but older than the copy this Smalti ships.
    case outdated
    case unknown
}
