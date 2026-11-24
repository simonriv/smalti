import Foundation
import SmaltiCore
import Testing

/// What every `ImageFiles` does with the same files: an image, a text file and a path that does not exist.
public struct ImageFilesSample: Sendable {
    public let files: any ImageFiles
    /// A 1440×900 image named `landing-v3.png`.
    public let image: String
    public let text: String
    public let missing: String

    public init(files: any ImageFiles, image: String, text: String, missing: String) {
        self.files = files
        self.image = image
        self.text = text
        self.missing = missing
    }
}

public enum ImageFilesContract {
    public static func verify(_ make: () async throws -> ImageFilesSample) async throws {
        let sample = try await make()
        let image = try await sample.files.describe(sample.image)
        #expect(image.name == "landing-v3.png")
        #expect(image.path == sample.image)
        #expect(image.dimensions == "1440×900")
        await #expect(throws: ImagePreviewError.notImage(path: sample.text)) {
            try await sample.files.describe(sample.text)
        }
        await #expect(throws: ImagePreviewError.notFound(path: sample.missing)) {
            try await sample.files.describe(sample.missing)
        }
        let png = try await sample.files.thumbnail(of: sample.image, fitting: Size(width: 388, height: 208))
        #expect(png.prefix(8) == Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]))
    }
}
