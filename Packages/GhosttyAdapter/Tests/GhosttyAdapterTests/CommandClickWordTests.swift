import Testing

@testable import GhosttyAdapter

/// libghostty ends a word at ":" (`selection-word-chars`); ⌘-click on `src/a.ts:12:3` must still get the line.
@Suite("CommandClickWord")
struct CommandClickWordTests {
    @Test func appendsLineAndColumnAfterTheWord() {
        #expect(CommandClickWord.extended("src/a.ts", row: "error src/a.ts:12:3 here", column: 6) == "src/a.ts:12:3")
    }

    @Test func appendsOnlyTheLine() {
        #expect(CommandClickWord.extended("/w/notes.txt", row: "/w/notes.txt:150", column: 0) == "/w/notes.txt:150")
    }

    @Test func keepsAWordWithoutLine() {
        #expect(CommandClickWord.extended("blob.bin", row: "blob.bin: data", column: 0) == "blob.bin")
        #expect(CommandClickWord.extended("a.ts", row: "a.ts 12", column: 0) == "a.ts")
    }

    @Test func usesTheOccurrenceAtTheClickedColumn() {
        #expect(CommandClickWord.extended("a.ts", row: "a.ts a.ts:9", column: 5) == "a.ts:9")
    }

    @Test func wordMissingFromTheRowIsKept() {
        #expect(CommandClickWord.extended("a.ts", row: "", column: 0) == "a.ts")
    }
}
