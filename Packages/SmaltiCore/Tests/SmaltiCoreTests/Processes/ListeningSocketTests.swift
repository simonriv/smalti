import SmaltiCore
import Testing

@Suite("ListeningSocket scope")
struct ListeningSocketTests {
    @Test(arguments: ["127.0.0.1", "127.0.1.1", "::1", "::ffff:127.0.0.1"])
    func loopbackIsLocal(address: String) {
        #expect(ListenScope.of([address]) == .local)
    }

    @Test(arguments: ["0.0.0.0", "::", "*"])
    func wildcardIsAll(address: String) {
        #expect(ListenScope.of([address]) == .all)
    }

    @Test func concreteAddressIsSpecific() {
        #expect(ListenScope.of(["192.168.1.20"]) == .specific(["192.168.1.20"]))
    }

    @Test func anyWildcardMakesTheGroupAll() {
        #expect(ListenScope.of(["127.0.0.1", "::"]) == .all)
    }

    @Test func loopbackPairStaysLocal() {
        #expect(ListenScope.of(["127.0.0.1", "::1"]) == .local)
    }

    @Test func mixedLoopbackAndConcreteListsTheConcreteOnes() {
        #expect(ListenScope.of(["127.0.0.1", "10.0.0.2"]) == .specific(["10.0.0.2"]))
    }

    @Test func isOpenToNetworkOnlyWhenNotLocal() {
        #expect(!ListenScope.local.isOpenToNetwork)
        #expect(ListenScope.all.isOpenToNetwork)
        #expect(ListenScope.specific(["10.0.0.2"]).isOpenToNetwork)
    }
}
