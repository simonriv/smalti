import Foundation
import SmaltiCore
import Testing

@Suite("BuildIdentity")
struct BuildIdentityTests {
    private let home = URL(filePath: "/Users/simon")

    @Test func devSuffixMeansDevelopment() {
        let identity = BuildIdentity(bundleIdentifier: "dev.simonriv.smalti.dev", productName: "Smalti Dev")

        #expect(identity.isDevelopment)
    }

    @Test func releaseIdentifierIsNotDevelopment() {
        let identity = BuildIdentity(bundleIdentifier: "dev.simonriv.smalti", productName: "Smalti")

        #expect(!identity.isDevelopment)
    }

    @Test func stateDirectoryIsNamedAfterTheProduct() {
        let identity = BuildIdentity(bundleIdentifier: "dev.simonriv.smalti.dev", productName: "Smalti Dev")

        #expect(
            identity.defaultStateDirectory(home: home)
                == URL(filePath: "/Users/simon/Library/Application Support/Smalti Dev"))
    }

    @Test func missingBundleValuesFallBackToTheDevelopmentIdentity() {
        let identity = BuildIdentity(bundleIdentifier: nil, productName: nil)

        #expect(identity == BuildIdentity.development)
        #expect(identity.isDevelopment)
    }

    @Test func missingProductNameAloneAlsoFallsBackToDevelopment() {
        let identity = BuildIdentity(bundleIdentifier: "dev.simonriv.smalti", productName: nil)

        #expect(identity == BuildIdentity.development)
    }
}
