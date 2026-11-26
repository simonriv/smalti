import Foundation
import SmaltiCore
import SmaltiCoreTestSupport
import Testing

@testable import GhosttyAdapter

@Suite("Terminal action bindings")
struct TerminalActionBindingTests {
    /// The names verified against libghostty v1.4.0 in `LibghosttyF45ApiTests` (F4.5 T1).
    @Test(arguments: [
        (TerminalAction.copy, "copy_to_clipboard:mixed"), (.paste, "paste_from_clipboard"), (.selectAll, "select_all"),
        (.clear, "clear_screen"), (.scroll(.pageUp), "scroll_page_up"), (.scroll(.pageDown), "scroll_page_down"),
        (.scroll(.top), "scroll_to_top"), (.scroll(.bottom), "scroll_to_bottom"),
        (.jumpToPrompt(.previous), "jump_to_prompt:-1"), (.jumpToPrompt(.next), "jump_to_prompt:1"),
    ])
    func everyActionMapsToVerifiedBinding(_ action: TerminalAction, _ binding: String) {
        #expect(TerminalActionBinding.action(for: action) == binding)
    }

    @Test func searchBindingCarriesTheText() {
        #expect(TerminalActionBinding.search("a b") == "search:a b")
    }

    @Test(arguments: [(SearchDirection.next, "navigate_search:next"), (.previous, "navigate_search:previous")])
    func navigationBindings(_ direction: SearchDirection, _ binding: String) {
        #expect(TerminalActionBinding.navigate(direction) == binding)
    }
}

@MainActor
@Suite("GhosttyTerminalEngine · F4.5 contract", .serialized)
struct GhosttyEngineActionsContractTests {
    @Test func ghosttyMeetsTheActionsContract() throws {
        try TestGhostty.initialize()
        let config = try GhosttyConfig.load(
            text: GhosttyConfigText.render(Theme.obsidian.terminal),
            writingTo: FileManager.default.temporaryDirectory.appending(path: "smalti-contract-\(UUID()).conf"))
        let runtime = try GhosttyRuntime(config: config, texts: .spanish)

        try TerminalEngineActionsContract.verify { GhosttyTerminalEngine(runtime: runtime) }
    }
}
