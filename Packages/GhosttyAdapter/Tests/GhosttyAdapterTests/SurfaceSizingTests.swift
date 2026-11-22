import GhosttyAdapter
import Testing

@Suite("Surface sizing")
struct SurfaceSizingTests {
    @Test func scalesPointsToPixels() {
        let size = SurfaceSizing.pixelSize(points: (width: 100, height: 50), scale: 2)
        #expect(size.width == 200 && size.height == 100)
    }

    @Test func neverReturnsZero() {
        let size = SurfaceSizing.pixelSize(points: (width: 0, height: 0), scale: 2)
        #expect(size.width == 1 && size.height == 1)
    }

    @Test func clampsNegativeWidth() {
        let size = SurfaceSizing.pixelSize(points: (width: -5, height: 10), scale: 2)
        #expect(size.width == 1 && size.height == 20)
    }

    @Test func roundsDown() {
        let size = SurfaceSizing.pixelSize(points: (width: 100.6, height: 50.2), scale: 1)
        #expect(size.width == 100 && size.height == 50)
    }
}
