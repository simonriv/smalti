import SmaltiCore
import Testing

/// Spec F5.5, "Miniatura al pasar el cursor": from the word under the pointer to the paths that may hold the image.
@Suite("PreviewCandidates")
struct PreviewCandidatesTests {
    private let context = PreviewContext(workingDirectory: "/w", home: "/h", lastCommand: nil)

    @Test func absolutePathIsOnlyCandidate() {
        #expect(PreviewCandidates.paths(for: "/tmp/a.png", in: context) == ["/tmp/a.png"])
    }

    @Test func relativeResolvesAgainstWorkingDirectory() {
        #expect(PreviewCandidates.paths(for: "a.png", in: context) == ["/w/a.png"])
    }

    @Test func relativeWithFolderResolvesAgainstWorkingDirectory() {
        #expect(PreviewCandidates.paths(for: "shots/a.png", in: context) == ["/w/shots/a.png"])
    }

    @Test func tildeExpandsWithHome() {
        #expect(PreviewCandidates.paths(for: "~/x.JPG", in: context) == ["/h/x.JPG"])
    }

    @Test func lastCommandDirectoryArgumentIsCandidate() {
        let context = PreviewContext(workingDirectory: "/w", home: "/h", lastCommand: "ls -la shots/ ../o")

        let paths = PreviewCandidates.paths(for: "a.png", in: context)

        #expect(paths == ["/w/a.png", "/w/shots/a.png", "/o/a.png"])
    }

    @Test func quotedArgumentWithSpaceIsOneDirectory() {
        let context = PreviewContext(workingDirectory: "/w", home: "/h", lastCommand: "ls 'mis fotos' \"otra carpeta\"")

        let paths = PreviewCandidates.paths(for: "a.png", in: context)

        #expect(paths == ["/w/a.png", "/w/mis fotos/a.png", "/w/otra carpeta/a.png"])
    }

    @Test func absoluteAndTildeArgumentsAreCandidates() {
        let context = PreviewContext(workingDirectory: "/w", home: "/h", lastCommand: "ls /srv/img ~/Desktop")

        let paths = PreviewCandidates.paths(for: "a.png", in: context)

        #expect(paths == ["/w/a.png", "/srv/img/a.png", "/h/Desktop/a.png"])
    }

    @Test func otherUsersTildeGivesNoCandidates() {
        #expect(PreviewCandidates.paths(for: "~ana/x.png", in: context).isEmpty)
    }

    @Test func lastSimpleCommandOfLineIsUsed() {
        let context = PreviewContext(workingDirectory: "/w", home: "/h", lastCommand: "cd docs && ls shots")

        #expect(PreviewCandidates.paths(for: "a.png", in: context) == ["/w/a.png", "/w/shots/a.png"])
    }

    @Test func duplicateCandidatesAppearOnce() {
        let context = PreviewContext(workingDirectory: "/w", home: "/h", lastCommand: "ls . ./")

        #expect(PreviewCandidates.paths(for: "a.png", in: context) == ["/w/a.png"])
    }

    @Test func absoluteWordIgnoresLastCommand() {
        let context = PreviewContext(workingDirectory: "/w", home: "/h", lastCommand: "ls shots")

        #expect(PreviewCandidates.paths(for: "/tmp/a.png", in: context) == ["/tmp/a.png"])
    }

    @Test(arguments: ["\"a.png\",", "'a.png':", "a.png,", "a.png:", "(a.png)"])
    func trailingPunctuationAndQuotesAreTrimmed(_ word: String) {
        #expect(PreviewCandidates.paths(for: word, in: context) == ["/w/a.png"])
    }

    @Test(arguments: ["notes.md", "a.png.txt", "png", ".png", ""])
    func nonImageExtensionGivesNoCandidates(_ word: String) {
        #expect(PreviewCandidates.paths(for: word, in: context).isEmpty)
    }

    @Test func uppercaseExtensionIsImage() {
        #expect(PreviewCandidates.paths(for: "A.HEIC", in: context) == ["/w/A.HEIC"])
    }

    @Test func missingWorkingDirectoryKeepsOnlyAbsolute() {
        let context = PreviewContext(workingDirectory: nil, home: "/h", lastCommand: "ls shots")

        #expect(PreviewCandidates.paths(for: "a.png", in: context).isEmpty)
        #expect(PreviewCandidates.paths(for: "/tmp/a.png", in: context) == ["/tmp/a.png"])
    }

    @Test func hostileWordStaysLiteralPath() {
        #expect(PreviewCandidates.paths(for: "$(touch pwned).png", in: context) == ["/w/$(touch pwned).png"])
    }

    @Test func dotSegmentsAreNormalized() {
        #expect(PreviewCandidates.paths(for: "../x/./a.png", in: context) == ["/x/a.png"])
    }

    @Test(arguments: ["png", "jpg", "jpeg", "gif", "heic", "heif", "webp", "tiff", "tif", "bmp"])
    func admittedExtensionsAreImages(_ ext: String) {
        #expect(ImageFileKind.isImage("a.\(ext)"))
    }

    @Test(arguments: ["a.svg", "a.pdf", "a.png.bak", "png"])
    func otherNamesAreNotImages(_ name: String) {
        #expect(!ImageFileKind.isImage(name))
    }
}
