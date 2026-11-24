import AppKit
import Darwin
import Foundation
import ImageIO
import ImageIOAdapter
import SmaltiCore
import SmaltiCoreTestSupport
import Testing
import UniformTypeIdentifiers

/// Spec F5.5: images are described from their header and reduced without decoding them whole; anything that is not
/// a regular image file is refused at once, and the size limits hold before any pixel is read.
@Suite("ImageIOImageFiles")
struct ImageIOImageFilesTests {
    private let files = ImageIOImageFiles()

    @Test func fulfillsTheContract() async throws {
        let fixtures = try ImageFixtures()
        try await ImageFilesContract.verify {
            ImageFilesSample(
                files: files, image: try fixtures.image("landing-v3.png", width: 1440, height: 900),
                text: try fixtures.text("notes.png"), missing: fixtures.path("none.png"))
        }
    }

    @Test func describeReadsSizeWithoutDecoding() async throws {
        let fixtures = try ImageFixtures()
        fixtures.isNoisy = true
        let path = try fixtures.image("photo.png", width: 4000, height: 3000)
        let start = ContinuousClock.now

        let image = try await files.describe(path)

        #expect(image.pixelWidth == 4000 && image.pixelHeight == 3000)
        #expect(ContinuousClock.now - start < .milliseconds(150))
    }

    @Test func imageOverMegapixelLimitIsTooLarge() async throws {
        let fixtures = try ImageFixtures()
        let path = try fixtures.image("wide.png", width: 2000, height: 1000)
        let strict = ImageIOImageFiles(maxBytes: 200_000_000, maxMegapixels: 1)

        await #expect(throws: ImagePreviewError.tooLarge(path: path, reason: "2000000 pixels (max 1000000)")) {
            try await strict.describe(path)
        }
        await #expect(throws: ImagePreviewError.self) {
            try await strict.thumbnail(of: path, fitting: Size(width: 388, height: 208))
        }
    }

    /// Block 2 review m1: "más de 100 megapíxeles" exactly: the limit itself passes, one pixel more does not.
    @Test func megapixelLimitIsExact() async throws {
        let fixtures = try ImageFixtures()
        let atLimit = try fixtures.image("limit.png", width: 1000, height: 1000)
        let over = try fixtures.image("over.png", width: 1000, height: 1001)
        let strict = ImageIOImageFiles(maxBytes: 200_000_000, maxMegapixels: 1)

        #expect(try await strict.describe(atLimit).dimensions == "1000×1000")
        await #expect(throws: ImagePreviewError.tooLarge(path: over, reason: "1001000 pixels (max 1000000)")) {
            try await strict.describe(over)
        }
    }

    @Test func fileOverByteLimitIsTooLarge() async throws {
        let fixtures = try ImageFixtures()
        let path = try fixtures.image("a.png", width: 64, height: 64)
        let small = ImageIOImageFiles(maxBytes: 10, maxMegapixels: 100)

        await #expect(throws: ImagePreviewError.self) { try await small.describe(path) }
        do {
            _ = try await small.describe(path)
        } catch .tooLarge(let tooLarge, _) {
            #expect(tooLarge == path)
        } catch {
            Issue.record("expected tooLarge, got \(error)")
        }
    }

    /// ImageIO paints what a cut file still has, as Preview does: a partial thumbnail or an error, never a crash.
    @Test func truncatedPngGivesPartialThumbnailOrError() async throws {
        let fixtures = try ImageFixtures()
        let path = try fixtures.truncatedPNG("cut.png")

        #expect(try await files.describe(path).dimensions == "400×300")
        let result: Result<Data, ImagePreviewError>
        do {
            result = .success(try await files.thumbnail(of: path, fitting: Size(width: 388, height: 208)))
        } catch {
            result = .failure(error)
        }
        switch result {
        case .success(let png): #expect(try pixelSize(png) == (width: 277, height: 208))
        case .failure(let error): #expect(error == .unreadable(path: path, reason: "ImageIO could not decode it"))
        }
    }

    @Test func pngSignatureWithGarbageIsNotAnImage() async throws {
        let fixtures = try ImageFixtures()
        let path = fixtures.path("fake.png")
        try Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A] + Array("garbage".utf8)).write(
            to: URL(fileURLWithPath: path))

        await #expect(throws: ImagePreviewError.notImage(path: path)) { try await files.describe(path) }
    }

    @Test func symlinkToDeviceIsRejected() async throws {
        let fixtures = try ImageFixtures()
        let path = fixtures.path("x.png")
        try FileManager.default.createSymbolicLink(atPath: path, withDestinationPath: "/dev/zero")

        await #expect(throws: ImagePreviewError.notImage(path: path)) { try await files.describe(path) }
    }

    @Test func symlinkToImageIsFollowed() async throws {
        let fixtures = try ImageFixtures()
        let target = try fixtures.image("real.png", width: 10, height: 20)
        let path = fixtures.path("link.png")
        try FileManager.default.createSymbolicLink(atPath: path, withDestinationPath: target)

        #expect(try await files.describe(path).dimensions == "10×20")
    }

    @Test func fifoIsRejectedWithoutBlocking() async throws {
        let fixtures = try ImageFixtures()
        let path = fixtures.path("y.png")
        #expect(mkfifo(path, 0o600) == 0)
        let start = ContinuousClock.now

        await #expect(throws: ImagePreviewError.notImage(path: path)) { try await files.describe(path) }
        #expect(ContinuousClock.now - start < .milliseconds(150))
    }

    @Test func folderIsNotAnImage() async throws {
        let fixtures = try ImageFixtures()
        let path = fixtures.path("shots.png")
        try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: false)

        await #expect(throws: ImagePreviewError.notImage(path: path)) { try await files.describe(path) }
    }

    @Test func unreadableFileFailsDescribe() async throws {
        let fixtures = try ImageFixtures()
        let path = try fixtures.image("locked.png", width: 10, height: 10)
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: path) }

        do {
            _ = try await files.describe(path)
            Issue.record("a file without permission was described")
        } catch .unreadable(let failed, _) {
            #expect(failed == path)
        } catch {
            Issue.record("expected unreadable, got \(error)")
        }
    }

    @Test func thumbnailFitsBox() async throws {
        let fixtures = try ImageFixtures()
        let path = try fixtures.image("big.png", width: 4000, height: 3000)

        let png = try await files.thumbnail(of: path, fitting: Size(width: 388, height: 208))

        let size = try pixelSize(png)
        #expect(abs(size.width - 277) <= 1 && size.height == 208)
    }

    /// XCUITest of F5.5 drew black thumbnails from a broken fixture; the adapter itself must keep the colors.
    @Test func thumbnailKeepsTheImageColors() async throws {
        let fixtures = try ImageFixtures()
        let path = try fixtures.image("blue.png", width: 320, height: 200)

        let png = try await files.thumbnail(of: path, fitting: Size(width: 96, height: 64))

        let source = try #require(CGImageSourceCreateWithData(png as CFData, nil))
        let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        let pixel = try #require(NSBitmapImageRep(cgImage: image).colorAt(x: 10, y: 10)?.usingColorSpace(.sRGB))
        // The fixture is drawn in the device space, so the sRGB values shift a little: blue stays dominant.
        #expect(pixel.blueComponent > 0.8 && pixel.redComponent < 0.4, "\(pixel)")
    }

    @Test func smallImageIsNotEnlarged() async throws {
        let fixtures = try ImageFixtures()
        let path = try fixtures.image("small.png", width: 40, height: 30)

        let png = try await files.thumbnail(of: path, fitting: Size(width: 388, height: 208))

        #expect(try pixelSize(png) == (width: 40, height: 30))
    }

    @Test(arguments: ["a.jpg", "a.heic", "a.tiff", "a.gif", "a.bmp"])
    func otherFormatsAreRead(_ name: String) async throws {
        let fixtures = try ImageFixtures()
        let type = try #require(UTType(filenameExtension: String(name.split(separator: ".")[1])))
        let path = try fixtures.image(name, width: 30, height: 20, type: type)

        #expect(try await files.describe(path).dimensions == "30×20")
        _ = try await files.thumbnail(of: path, fitting: Size(width: 388, height: 208))
    }

    private func pixelSize(_ png: Data) throws -> (width: Int, height: Int) {
        let source = try #require(CGImageSourceCreateWithData(png as CFData, nil))
        let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        return (image.width, image.height)
    }
}
