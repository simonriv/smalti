import Foundation
import SmaltiCore

/// The running build's identity, read once from the main bundle (the only place that reads it).
enum AppIdentity {
    static let current = BuildIdentity(
        bundleIdentifier: Bundle.main.bundleIdentifier,
        productName: Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String)
}
