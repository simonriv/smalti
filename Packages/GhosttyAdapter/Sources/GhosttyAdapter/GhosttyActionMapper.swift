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
            return f45Event(for: action)
        }
    }

    /// F4.5: search progress, link hover and secure input.
    private static func f45Event(for action: ghostty_action_s) -> TerminalEvent? {
        switch action.tag {
        case GHOSTTY_ACTION_SEARCH_TOTAL:
            return .searchTotal(count(action.action.search_total.total))
        case GHOSTTY_ACTION_SEARCH_SELECTED:
            return .searchSelected(count(action.action.search_selected.selected))
        case GHOSTTY_ACTION_MOUSE_OVER_LINK:
            return .linkHovered(link(of: action))
        case GHOSTTY_ACTION_SECURE_INPUT:
            return secureInput(action.action.secure_input)
        default:
            return nil
        }
    }

    /// libghostty reports "no search" and "nothing selected" as a negative number.
    private static func count(_ value: Int) -> Int? {
        value < 0 ? nil : value
    }

    private static func link(of action: ghostty_action_s) -> String? {
        let hover = action.action.mouse_over_link
        guard let pointer = hover.url, hover.len > 0 else { return nil }
        // Safe: libghostty guarantees `len` bytes at `url` for the duration of the callback.
        return String(decoding: UnsafeRawBufferPointer(start: pointer, count: hover.len), as: UTF8.self)
    }

    /// TOGGLE never comes from the terminal itself (only from a binding Smalti does not set), so it maps to nil.
    private static func secureInput(_ value: ghostty_action_secure_input_e) -> TerminalEvent? {
        switch value {
        case GHOSTTY_SECURE_INPUT_ON: .secureInputRequested(true)
        case GHOSTTY_SECURE_INPUT_OFF: .secureInputRequested(false)
        default: nil
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
