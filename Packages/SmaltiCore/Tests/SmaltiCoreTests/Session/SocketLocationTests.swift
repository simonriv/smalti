import Foundation
import SmaltiCore
import Testing

@Suite("Socket location")
struct SocketLocationTests {
    @Test func socketLivesInTheStateDirectoryWhenItFits() {
        let state = URL(filePath: "/Users/s/Library/Application Support/Smalti Dev")

        #expect(SocketLocation.socketFile(stateDirectory: state) == state.appending(path: "smalti.sock"))
    }

    @Test func aStateDirectoryTooDeepForASocketUsesAShortStablePath() {
        let state = URL(
            filePath:
                "/Users/s/Library/Containers/dev.simonriv.smalti.uitests.xctrunner/Data/tmp/smalti-ui-tests-8D8AC610-566D-4EF0-9C22-186B2A5ED793/state"
        )

        let socket = SocketLocation.socketFile(stateDirectory: state)

        #expect(socket.path(percentEncoded: false).utf8.count < SocketLocation.maximumPathBytes)
        #expect(socket == SocketLocation.socketFile(stateDirectory: state))
        #expect(socket != SocketLocation.socketFile(stateDirectory: state.appending(path: "otro")))
        #expect(socket.path(percentEncoded: false).hasPrefix("/tmp/smalti-"))
    }

    @Test func limitIsTheSizeOfASocketAddressPath() {
        #expect(SocketLocation.maximumPathBytes == 104)
    }
}
