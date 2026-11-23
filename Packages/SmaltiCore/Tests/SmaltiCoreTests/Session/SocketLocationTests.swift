import Foundation
import SmaltiCore
import Testing

@Suite("Socket location")
struct SocketLocationTests {
    /// The user's private temporary directory, not the shared /tmp.
    private let temporary = URL(
        filePath: "/var/folders/mx/whd_9sq97dx3gdskngzqjc4c0000gn/T", directoryHint: .isDirectory)
    @Test func socketLivesInTheStateDirectoryWhenItFits() {
        let state = URL(filePath: "/Users/s/Library/Application Support/Smalti Dev")

        #expect(
            SocketLocation.socketFile(stateDirectory: state, temporaryDirectory: temporary)
                == state.appending(path: "smalti.sock"))
    }

    @Test func aStateDirectoryTooDeepForASocketUsesAShortStablePath() {
        let state = URL(
            filePath:
                "/Users/s/Library/Containers/dev.simonriv.smalti.uitests.xctrunner/Data/tmp/smalti-ui-tests-8D8AC610-566D-4EF0-9C22-186B2A5ED793/state"
        )

        let socket = SocketLocation.socketFile(stateDirectory: state, temporaryDirectory: temporary)

        #expect(socket.path(percentEncoded: false).utf8.count < SocketLocation.maximumPathBytes)
        #expect(socket == SocketLocation.socketFile(stateDirectory: state, temporaryDirectory: temporary))
        #expect(
            socket
                != SocketLocation.socketFile(
                    stateDirectory: state.appending(path: "otro"), temporaryDirectory: temporary))
        #expect(socket.deletingLastPathComponent() == temporary)
        #expect(socket.lastPathComponent.hasPrefix("smalti-"))
    }

    @Test func limitIsTheSizeOfASocketAddressPath() {
        #expect(SocketLocation.maximumPathBytes == 104)
    }
}
