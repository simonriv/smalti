import SmaltiCore

/// libghostty binding-action names for Smalti's terminal actions, as verified against v1.4.0 (F4.5 T1).
enum TerminalActionBinding {
    static func action(for action: TerminalAction) -> String {
        switch action {
        case .copy: "copy_to_clipboard:mixed"
        case .paste: "paste_from_clipboard"
        case .selectAll: "select_all"
        case .clear: "clear_screen"
        case .scroll(let target): scroll(target)
        case .jumpToPrompt(.previous): "jump_to_prompt:-1"
        case .jumpToPrompt(.next): "jump_to_prompt:1"
        }
    }

    static func search(_ text: String) -> String { "search:" + text }

    static func navigate(_ direction: SearchDirection) -> String {
        switch direction {
        case .next: "navigate_search:next"
        case .previous: "navigate_search:previous"
        }
    }

    static let endSearch = "end_search"

    private static func scroll(_ target: ScrollTarget) -> String {
        switch target {
        case .pageUp: "scroll_page_up"
        case .pageDown: "scroll_page_down"
        case .top: "scroll_to_top"
        case .bottom: "scroll_to_bottom"
        }
    }
}
