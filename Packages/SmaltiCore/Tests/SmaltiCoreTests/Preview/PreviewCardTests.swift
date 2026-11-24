import Foundation
import SmaltiCore
import Testing

/// Spec F5.5: the card's caption, as `Main.dc.html` writes it, with "⌘Y para abrir".
@Suite("PreviewCard")
struct PreviewCardTests {
    private let anchor = Rect(x: 0, y: 0, width: 10, height: 10)

    private func image(_ name: String) -> ImageDescription {
        ImageDescription(path: "/w/\(name)", name: name, pixelWidth: 1440, pixelHeight: 900)
    }

    @Test func captionHasNameSizeAndShortcut() {
        let card = PreviewCard.image(image("landing-v3.png"), thumbnail: Data([1]), anchor: anchor)

        #expect(card.caption == "landing-v3.png · 1440×900 · ⌘Y para abrir")
    }

    @Test func longNameIsCutInTheMiddle() {
        let card = PreviewCard.image(
            image("captura-de-pantalla-2026-11-24-a-las-09.png"), thumbnail: Data([1]), anchor: anchor)

        #expect(card.caption == "captura-de-pan…-a-las-09.png · 1440×900 · ⌘Y para abrir")
    }

    @Test func nameOf28IsKept() {
        let name = String(repeating: "a", count: 24) + ".png"

        #expect(PreviewCard.unreadable(image(name), anchor: anchor).caption == "\(name) · No se pudo leer la imagen")
    }

    @Test func controlCharactersInNameAreReplaced() {
        let card = PreviewCard.unreadable(image("a\u{1B}[2J.png"), anchor: anchor)

        #expect(card.caption == "a?[2J.png · No se pudo leer la imagen")
    }

    @Test func tooLargeUsesTheFileName() {
        let card = PreviewCard.tooLarge(path: "/w/shots/big.png", anchor: anchor)

        #expect(card.caption == "big.png · Imagen demasiado grande")
        #expect(card.thumbnail == nil)
        #expect(card.path == "/w/shots/big.png")
    }
}
