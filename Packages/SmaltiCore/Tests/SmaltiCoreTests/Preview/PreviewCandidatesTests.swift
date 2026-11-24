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

        #expect(paths == ["/w/shots/a.png", "/o/a.png", "/w/a.png"])
    }

    @Test func quotedArgumentWithSpaceIsOneDirectory() {
        let context = PreviewContext(workingDirectory: "/w", home: "/h", lastCommand: "ls 'mis fotos' \"otra carpeta\"")

        let paths = PreviewCandidates.paths(for: "a.png", in: context)

        #expect(paths == ["/w/mis fotos/a.png", "/w/otra carpeta/a.png", "/w/a.png"])
    }

    @Test func absoluteAndTildeArgumentsAreCandidates() {
        let context = PreviewContext(workingDirectory: "/w", home: "/h", lastCommand: "ls /srv/img ~/Desktop")

        let paths = PreviewCandidates.paths(for: "a.png", in: context)

        #expect(paths == ["/srv/img/a.png", "/h/Desktop/a.png", "/w/a.png"])
    }

    @Test func otherUsersTildeGivesNoCandidates() {
        #expect(PreviewCandidates.paths(for: "~ana/x.png", in: context).isEmpty)
    }

    @Test func everyCommandOfTheLineIsUsed() {
        let context = PreviewContext(workingDirectory: "/w", home: "/h", lastCommand: "cd docs && ls shots")

        #expect(PreviewCandidates.paths(for: "a.png", in: context) == ["/w/docs/a.png", "/w/shots/a.png", "/w/a.png"])
    }

    @Test func pipelineArgumentsAreCandidates() {
        let context = PreviewContext(workingDirectory: "/w", home: "/h", lastCommand: "ls -t shots | head -5")

        #expect(PreviewCandidates.paths(for: "a.png", in: context) == ["/w/shots/a.png", "/w/a.png"])
    }

    /// Block 1 review: with `a.png` in both, `ls shots/` printed the one in shots, never the parent's.
    @Test func commandDirectoriesComeBeforeWorkingDirectory() {
        let context = PreviewContext(workingDirectory: "/w", home: "/h", lastCommand: "ls shots/")

        #expect(PreviewCandidates.paths(for: "a.png", in: context).first == "/w/shots/a.png")
    }

    @Test(arguments: ["ls shots > out.txt", "ls shots 2>&1", "ls shots >out.txt", "ls shots &> log", "ls shots < in"])
    func redirectionsAreNotCandidates(_ command: String) {
        let context = PreviewContext(workingDirectory: "/w", home: "/h", lastCommand: command)

        #expect(PreviewCandidates.paths(for: "a.png", in: context) == ["/w/shots/a.png", "/w/a.png"])
    }

    @Test func wordAfterRedirectTargetIsCandidate() {
        let context = PreviewContext(workingDirectory: "/w", home: "/h", lastCommand: "ls > out.txt shots")

        #expect(PreviewCandidates.paths(for: "a.png", in: context) == ["/w/shots/a.png", "/w/a.png"])
    }

    @Test(arguments: ["ls shots <in", "ls shots &>log", "ls shots 2>err"])
    func attachedRedirectionsAreNotCandidates(_ command: String) {
        let context = PreviewContext(workingDirectory: "/w", home: "/h", lastCommand: command)

        #expect(PreviewCandidates.paths(for: "a.png", in: context) == ["/w/shots/a.png", "/w/a.png"])
    }

    @Test func folderNamedLikeAnImageIsNotAnImage() {
        #expect(!ImageFileKind.isImage("shots.png/"))
    }

    @Test func trailingPeriodIsTrimmed() {
        #expect(PreviewCandidates.paths(for: "out.png.", in: context) == ["/w/out.png"])
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
