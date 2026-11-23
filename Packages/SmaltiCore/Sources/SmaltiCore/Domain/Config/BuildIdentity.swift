import Foundation

/// Which build is running: the daily Release ("Smalti", `dev.simonriv.smalti`) or a development build ("Smalti Dev",
/// `dev.simonriv.smalti.dev`). Each keeps its own state directory and socket, so tests and scripts that drive the
/// development build never touch the daily one (spec F2, part A).
public struct BuildIdentity: Equatable, Sendable {
    public static let developmentSuffix = ".dev"
    /// Used when the bundle does not say who it is: the safe side is never to touch the daily build's state.
    public static let development = BuildIdentity(
        bundleIdentifier: "dev.simonriv.smalti\(developmentSuffix)", productName: "Smalti Dev")

    public let bundleIdentifier: String
    public let productName: String

    public init(bundleIdentifier: String, productName: String) {
        self.bundleIdentifier = bundleIdentifier
        self.productName = productName
    }

    /// From the bundle's own values; any missing one falls back to `development`.
    public init(bundleIdentifier: String?, productName: String?) {
        guard let bundleIdentifier, let productName else {
            self = .development
            return
        }
        self.init(bundleIdentifier: bundleIdentifier, productName: productName)
    }

    public var isDevelopment: Bool { bundleIdentifier.hasSuffix(Self.developmentSuffix) }

    /// `~/Library/Application Support/<product name>/`.
    public func defaultStateDirectory(home: URL) -> URL {
        home.appending(path: "Library/Application Support").appending(path: productName)
    }
}
