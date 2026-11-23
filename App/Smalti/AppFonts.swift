import CoreText
import Foundation
import OSLog

/// Inter ships with the app (SIL OFL 1.1, Fonts/LICENSE-Inter.txt) so the interface looks the same on any Mac.
enum AppFonts {
    private static let logger = Logger(subsystem: AppIdentity.current.bundleIdentifier, category: "fonts")

    /// Registers every bundled TrueType font for this process only. A failure leaves the system fallback.
    static func registerBundled() {
        let urls = ["Fonts", nil].flatMap { Bundle.main.urls(forResourcesWithExtension: "ttf", subdirectory: $0) ?? [] }
        for url in Set(urls) {
            var error: Unmanaged<CFError>?
            guard !CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error) else { continue }
            let reason = error.map { String(describing: $0.takeRetainedValue()) } ?? "unknown"
            logger.error("font not registered: \(url.lastPathComponent, privacy: .public): \(reason, privacy: .public)")
        }
    }
}
