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

    // Review I8: a space (or any edit outside the word) closes the menu.
    @Test func typingASpaceClosesTheMenu() {
        var menu = openMenu()

        #expect(menu.lineChanged(InputLine(text: "git ch ", cursor: 7)) == .close)
        #expect(!menu.isOpen)
    }

    @Test func editingBeforeTheWordClosesTheMenu() {
        var menu = openMenu()

        #expect(menu.lineChanged(InputLine(text: "gitx ch", cursor: 7)) == .close)
    }

    // Review m1: generated items for another request are dropped.
    @Test func generatedItemsForAnotherLineAreIgnored() {
        var menu = openMenu()

        #expect(
            menu.addGenerated([Suggestion(name: "chx")], for: InputLine(text: "git add ch", cursor: 10))
                == MenuEffect.none)
        #expect(menu.visible.count == 3)
    }

    @Test func generatedItemsStillApplyAfterRefiltering() {
        var menu = openMenu()
        _ = menu.lineChanged(InputLine(text: "git che", cursor: 7))

        #expect(menu.addGenerated([Suggestion(name: "chess")], for: gitCh) == .show)
        #expect(menu.visible.map(\.name).contains("chess"))
    }

    // Review m2: the common prefix must extend what was typed.
    @Test func fuzzyOnlyItemsDoNotRewriteTheWord() {
        var menu = CompletionMenu()
        let line = InputLine(text: "x a", cursor: 3)
        menu.request(for: line)

        #expect(menu.receive([Suggestion(name: "bar"), Suggestion(name: "baz")], for: line) == .show)
    }

    // Review m3: a single fuzzy match is shown, not inserted.
    @Test func singleFuzzyMatchOpensTheMenu() {
        var menu = CompletionMenu()
        let line = InputLine(text: "rm docs", cursor: 7)
        menu.request(for: line)

        #expect(menu.receive([Suggestion(name: "Documents/")], for: line) == .show)
    }

    // Review m4: refiltering keeps the selected suggestion when it is still visible.
    @Test func refilteringFollowsTheSelectedItem() {
        var menu = openMenu()
        _ = menu.press(.down)
        _ = menu.press(.down)

        _ = menu.lineChanged(InputLine(text: "git chm", cursor: 7))

        #expect(menu.visible[menu.selected].name == "chmod")
    }

    // Review I7: a target with generators waits for them before deciding.
    @Test func generatorOnlyTargetWaitsForGeneratedItems() {
        var menu = CompletionMenu()
        let line = InputLine(text: "git checkout ", cursor: 13)
        menu.request(for: line)

        #expect(menu.receive([], for: line, generating: true) == MenuEffect.none)
        #expect(menu.addGenerated([Suggestion(name: "main"), Suggestion(name: "dev")], for: line) == .show)
        #expect(menu.visible.map(\.name) == ["main", "dev"])
    }

    @Test func generatorsFindingNothingFallBack() {
        var menu = CompletionMenu()
        let line = InputLine(text: "git checkout ", cursor: 13)
        menu.request(for: line)
        _ = menu.receive([], for: line, generating: true)

        #expect(menu.addGenerated([], for: line) == .fallback)
    }

    @Test func singleGeneratedItemIsInserted() {
        var menu = CompletionMenu()
        let line = InputLine(text: "git checkout ", cursor: 13)
        menu.request(for: line)
        _ = menu.receive([], for: line, generating: true)

        #expect(
            menu.addGenerated([Suggestion(name: "main")], for: line)
                == .insert(InputLine(text: "git checkout main ", cursor: 18)))
    }

    @Test func singleFixedItemWaitsWhileGenerating() {
        var menu = CompletionMenu()
        menu.request(for: gitCh)

        #expect(menu.receive([Suggestion(name: "checkout")], for: gitCh, generating: true) == .show)
        #expect(menu.isOpen)
    }
}
