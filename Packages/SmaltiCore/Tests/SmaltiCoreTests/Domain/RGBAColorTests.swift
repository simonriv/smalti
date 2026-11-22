import SmaltiCore
import Testing

@Suite("RGBAColor")
struct RGBAColorTests {
    @Test func parsesHexWithFullAlpha() throws {
        #expect(try RGBAColor(hex: "#7aa2f7") == RGBAColor(red: 122, green: 162, blue: 247, alpha: 1))
    }

    @Test(arguments: ["7aa2f7", "#zzzzzz", "#7aa2f", "#7aa2f7ff"])
    func rejectsMalformedHex(_ hex: String) {
        #expect(throws: ColorError.invalidHex(hex)) {
            try RGBAColor(hex: hex)
        }
    }
}
