import SmaltiCore
import Testing

@Suite("TokenUsage")
struct TokenUsageTests {
    @Test func inputTotalAddsCacheReadsAndWrites() {
        let usage = TokenUsage(input: 2, output: 122, cacheRead: 26_348, cacheWrite5m: 10, cacheWrite1h: 37_858)

        #expect(usage.inputTotal == 64_218)
    }

    @Test func cacheShareIsReadOverInputTotal() {
        let usage = TokenUsage(input: 100, output: 0, cacheRead: 300, cacheWrite5m: 0, cacheWrite1h: 0)

        #expect(usage.cacheShare == 0.75)
    }

    @Test func cacheShareIsNilWithoutInput() {
        #expect(TokenUsage.zero.cacheShare == nil)
    }

    @Test func usageAddsFieldByField() {
        let first = TokenUsage(input: 1, output: 2, cacheRead: 3, cacheWrite5m: 4, cacheWrite1h: 5)
        let second = TokenUsage(input: 10, output: 20, cacheRead: 30, cacheWrite5m: 40, cacheWrite1h: 50)

        #expect(first + second == TokenUsage(input: 11, output: 22, cacheRead: 33, cacheWrite5m: 44, cacheWrite1h: 55))
    }
}
