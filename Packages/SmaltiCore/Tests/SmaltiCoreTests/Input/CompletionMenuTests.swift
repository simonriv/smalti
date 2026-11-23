import SmaltiCore
import Testing

@Suite("CompletionMenu")
struct CompletionMenuTests {
    private let gitCh = InputLine(text: "git ch", cursor: 6)
    private let items = ["checkout", "cherry-pick", "chmod"].map { Suggestion(name: $0) }

    private func openMenu() -> CompletionMenu {
        var menu = CompletionMenu()
        menu.request(for: gitCh)
        _ = menu.receive(items, for: gitCh)
        return menu
    }

    @Test func menuZeroItemsFallsBack() {
        var menu = CompletionMenu()
        menu.request(for: gitCh)

        #expect(menu.receive([], for: gitCh) == .fallback)
        #expect(!menu.isOpen)
    }

    @Test func menuOneItemInsertsDirectly() {
        var menu = CompletionMenu()
        menu.request(for: gitCh)

        #expect(
            menu.receive([Suggestion(name: "checkout")], for: gitCh)
                == .insert(InputLine(text: "git checkout ", cursor: 13)))
        #expect(!menu.isOpen)
    }

    @Test func menuCommonPrefixInsertsThenShows() {
        var menu = CompletionMenu()
        let line = InputLine(text: "git c", cursor: 5)
        menu.request(for: line)

        let effect = menu.receive(items, for: line)

        #expect(effect == .insertThenShow(InputLine(text: "git ch", cursor: 6)))
        #expect(menu.isOpen)
    }

    @Test func menuShowsWithoutLongerCommonPrefix() {
        var menu = CompletionMenu()
        menu.request(for: gitCh)

        #expect(menu.receive(items, for: gitCh) == .show)
        #expect(menu.visible.map(\.name) == ["checkout", "cherry-pick", "chmod"])
        #expect(menu.selected == 0)
    }

    @Test func menuTabAndEnterInsertSelection() {
        var tab = openMenu()
        var enter = openMenu()
        _ = enter.press(.down)

        #expect(tab.press(.tab) == .insert(InputLine(text: "git checkout ", cursor: 13)))
        #expect(enter.press(.enter) == .insert(InputLine(text: "git cherry-pick ", cursor: 16)))
        #expect(!tab.isOpen && !enter.isOpen)
    }

    @Test func menuEscapeClosesWithoutChange() {
        var menu = openMenu()

        #expect(menu.press(.escape) == .close)
        #expect(!menu.isOpen)
    }

    @Test func menuOtherKeyCloses() {
        var menu = openMenu()

        #expect(menu.press(.other) == .close)
    }

    @Test func menuWrapsSelection() {
        var menu = openMenu()

        _ = menu.press(.up)
        #expect(menu.selected == 2)
        _ = menu.press(.down)
        #expect(menu.selected == 0)
    }

    @Test func menuRefiltersOnLineChange() {
        var menu = openMenu()

        let effect = menu.lineChanged(InputLine(text: "git chec", cursor: 8))

        #expect(effect == .show)
        #expect(menu.visible.map(\.name) == ["checkout", "cherry-pick"])
    }

    @Test func menuClosesWhenNothingMatches() {
        var menu = openMenu()

        #expect(menu.lineChanged(InputLine(text: "git chx", cursor: 7)) == .close)
        #expect(!menu.isOpen)
    }

    @Test func menuIgnoresItemsForOldLine() {
        var menu = CompletionMenu()
        menu.request(for: gitCh)

        #expect(menu.receive(items, for: InputLine(text: "git c", cursor: 5)) == MenuEffect.none)
    }

    @Test func typingWhileWaitingCancelsTheRequest() {
        var menu = CompletionMenu()
        menu.request(for: gitCh)

        _ = menu.lineChanged(InputLine(text: "git che", cursor: 7))

        #expect(menu.receive(items, for: gitCh) == MenuEffect.none)
    }

    @Test func keysOnAClosedMenuDoNothing() {
        var menu = CompletionMenu()

        #expect(menu.press(.enter) == MenuEffect.none)
    }

    @Test func lateItemsRefilterWithoutMovingSelection() {
        var menu = openMenu()
        _ = menu.press(.down)

        let effect = menu.addGenerated([Suggestion(name: "chmod-like")], for: gitCh)

        #expect(effect == .show)
        #expect(menu.selected == 1)
        #expect(menu.visible.count == 4)
    }

    @Test func commonPrefixWithSpacesIsEscaped() {
        var menu = CompletionMenu()
        let line = InputLine(text: "cd My", cursor: 5)
        menu.request(for: line)

        let effect = menu.receive([Suggestion(name: "My Folder/"), Suggestion(name: "My Files/")], for: line)

        #expect(effect == .insertThenShow(InputLine(text: "cd My\\ F", cursor: 8)))
    }
}
