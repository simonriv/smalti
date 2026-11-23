import Foundation

/// Which build is running: the daily Release ("Smalti", `dev.simonriv.smalti`) or a development build ("Smalti Dev",
/// `dev.simonriv.smalti.dev`). Each keeps its own state directory and socket, so tests and scripts that drive the
/// development build never touch the daily one (spec F2, part A). The only place that reads the bundle identity.
struct AppIdentity: Sendable {
    static let developmentSuffix = ".dev"
    static let releaseIdentifier = "dev.simonriv.smalti"
    static let current = AppIdentity(bundle: .main)

    let bundleIdentifier: String
    let productName: String

    var isDevelopment: Bool { bundleIdentifier.hasSuffix(Self.developmentSuffix) }

    init(bundleIdentifier: String, productName: String) {
        self.bundleIdentifier = bundleIdentifier
        self.productName = productName
    }

    private init(bundle: Bundle) {
        let identifier = bundle.bundleIdentifier ?? Self.releaseIdentifier
        let name = bundle.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "Smalti"
        self.init(bundleIdentifier: identifier, productName: name)
    }

    /// `~/Library/Application Support/<product name>/`.
    func defaultStateDirectory(home: URL) -> URL {
        home.appending(path: "Library/Application Support").appending(path: productName)
    }
}
