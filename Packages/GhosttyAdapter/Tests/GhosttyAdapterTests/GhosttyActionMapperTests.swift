import GhosttyAdapter
import GhosttyKit
import SmaltiCore
import Testing

@Suite("Ghostty action mapper")
struct GhosttyActionMapperTests {
    private func action(_ tag: ghostty_action_tag_e, _ fill: (inout ghostty_action_u) -> Void = { _ in })
        -> ghostty_action_s
    {
        var payload = ghostty_action_u()
        fill(&payload)
        return ghostty_action_s(tag: tag, action: payload)
    }

    @Test func setTitleBecomesTitleChanged() {
        "zsh".withCString { title in
            let event = GhosttyActionMapper.event(for: action(GHOSTTY_ACTION_SET_TITLE) { $0.set_title.title = title })
            #expect(event == .titleChanged("zsh"))
        }
    }

    @Test func absolutePwdBecomesWorkingDirectoryChanged() throws {
        let tmp = try WorkingDirectory(path: "/tmp")
        "/tmp".withCString { pwd in
            #expect(
                GhosttyActionMapper.event(for: action(GHOSTTY_ACTION_PWD) { $0.pwd.pwd = pwd })
                    == .workingDirectoryChanged(tmp))
        }
    }

    @Test func relativePwdIsIgnored() {
        "relative".withCString { pwd in
            #expect(GhosttyActionMapper.event(for: action(GHOSTTY_ACTION_PWD) { $0.pwd.pwd = pwd }) == nil)
        }
    }

    @Test func commandFinishedCarriesExitCodeAndDuration() {
        let event = GhosttyActionMapper.event(
            for: action(GHOSTTY_ACTION_COMMAND_FINISHED) {
                $0.command_finished = ghostty_action_command_finished_s(exit_code: 1, duration: 400_000_000)
            })

        #expect(event == .commandFinished(exitCode: 1, duration: .milliseconds(400)))
    }

    @Test func unreportedExitCodeIsNil() {
        let event = GhosttyActionMapper.event(
            for: action(GHOSTTY_ACTION_COMMAND_FINISHED) {
                $0.command_finished = ghostty_action_command_finished_s(exit_code: -1, duration: 0)
            })

        #expect(event == .commandFinished(exitCode: nil, duration: .zero))
    }

    @Test func ringBellBecomesBell() {
        #expect(GhosttyActionMapper.event(for: action(GHOSTTY_ACTION_RING_BELL)) == .bell)
    }

    @Test func childExitedBecomesExited() {
        let event = GhosttyActionMapper.event(
            for: action(GHOSTTY_ACTION_SHOW_CHILD_EXITED) {
                $0.child_exited = ghostty_surface_message_childexited_s(exit_code: 0, timetime_ms: 10)
            })

        #expect(event == .exited(code: 0))
    }

    @Test func unhandledActionIsIgnored() {
        #expect(GhosttyActionMapper.event(for: action(GHOSTTY_ACTION_NEW_SPLIT)) == nil)
    }
}
