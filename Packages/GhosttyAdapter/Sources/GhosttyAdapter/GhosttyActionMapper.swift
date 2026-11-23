import GhosttyKit
import SmaltiCore

/// Translates libghostty runtime actions into domain terminal events. Unhandled actions map to nil.
public enum GhosttyActionMapper {
    public static func event(for action: ghostty_action_s) -> TerminalEvent? {
        switch action.tag {
        case GHOSTTY_ACTION_SET_TITLE:
            return string(action.action.set_title.title).map(TerminalEvent.titleChanged)
        case GHOSTTY_ACTION_PWD:
            return string(action.action.pwd.pwd)
                .flatMap { try? WorkingDirectory(path: $0) }
                .map(TerminalEvent.workingDirectoryChanged)
        case GHOSTTY_ACTION_COMMAND_FINISHED:
            let finished = action.action.command_finished
            return .commandFinished(
                exitCode: finished.exit_code < 0 ? nil : Int(finished.exit_code),
                duration: .nanoseconds(Int64(clamping: finished.duration)))
        case GHOSTTY_ACTION_RING_BELL:
            return .bell
        case GHOSTTY_ACTION_SHOW_CHILD_EXITED:
            return .exited(code: Int(action.action.child_exited.exit_code))
        default:
            return nil
        }
    }

    private static func string(_ pointer: UnsafePointer<CChar>?) -> String? {
        pointer.map { String(cString: $0) }
    }

    /// The URL or path of an OPEN_URL action.
    static func url(of action: ghostty_action_s) -> String? {
        let open = action.action.open_url
        guard let pointer = open.url else { return nil }
        // Safe: libghostty guarantees `len` bytes at `url` for the duration of the callback.
        return String(decoding: UnsafeRawBufferPointer(start: pointer, count: Int(open.len)), as: UTF8.self)
    }
}
