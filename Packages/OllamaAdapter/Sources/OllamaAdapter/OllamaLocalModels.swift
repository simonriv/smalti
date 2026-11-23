import Foundation
import SmaltiCore

/// `LocalModels` from Ollama's local API: `/api/ps` (loaded) and `/api/tags` (on disk). Ollama is optional: no
/// answer within 500 ms, an error status or an unexpected body all mean "not running" for the card.
public struct OllamaLocalModels: LocalModels {
    private let baseURL: URL
    private let session: URLSession

    public static let timeout: Duration = .milliseconds(500)

    public init(baseURL: URL, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }

    /// Both listings are asked at once, so the card waits 500 ms at most.
    public func current() async -> LocalModelsReport {
        async let running = models(at: "api/ps")
        async let pulled = models(at: "api/tags")
        guard let loaded = await running?.map(\.model) else { return .unavailable }
        let names = Set(loaded.map(\.name))
        let onDisk = (await pulled ?? []).map(\.model).filter { !names.contains($0.name) }
        return .available(loaded: loaded, onDisk: onDisk)
    }

    /// One malformed entry is skipped, not allowed to hide every model.
    private struct Listing: Decodable {
        let models: [Entry]

        private enum CodingKeys: String, CodingKey { case models }

        init(from decoder: any Decoder) throws {
            var list = try decoder.container(keyedBy: CodingKeys.self).nestedUnkeyedContainer(forKey: .models)
            var entries: [Entry] = []
            while !list.isAtEnd {
                if let entry = try? list.decode(Entry.self) {
                    entries.append(entry)
                } else {
                    _ = try list.decode(Skipped.self)
                }
            }
            models = entries
        }
    }

    /// Consumes an entry that does not decode, so the list can go on.
    private struct Skipped: Decodable {}

    private struct Entry: Decodable {
        struct Details: Decodable {
            let quantizationLevel: String?

            enum CodingKeys: String, CodingKey { case quantizationLevel = "quantization_level" }
        }

        let name: String
        let size: UInt64
        let sizeVram: UInt64?
        let contextLength: Int?
        let modifiedAt: String?
        let details: Details?

        enum CodingKeys: String, CodingKey {
            case name, size, details
            case sizeVram = "size_vram"
            case contextLength = "context_length"
            case modifiedAt = "modified_at"
        }

        var model: LocalModel {
            LocalModel(
                name: name, quantization: details?.quantizationLevel, bytes: size, vramBytes: sizeVram,
                contextLength: contextLength, downloadedAt: modifiedAt.flatMap(OllamaDate.parse))
        }
    }

    /// The listing at `path`, or nil when Ollama does not answer in time or answers something else.
    private func models(at path: String) async -> [Entry]? {
        let request = URLRequest(url: baseURL.appending(path: path))
        let session = session
        return await withTaskGroup(of: [Entry]?.self) { group in
            group.addTask {
                guard let (data, response) = try? await session.data(for: request),
                    (response as? HTTPURLResponse)?.statusCode == 200
                else { return nil }
                return try? JSONDecoder().decode(Listing.self, from: data).models
            }
            group.addTask {
                try? await Task.sleep(for: Self.timeout)
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }
}

/// Ollama writes `modified_at` with nanoseconds ("…00.123456789-05:00"), more than ISO8601DateFormatter reads.
enum OllamaDate {
    private static let fractionDigits = 3

    static func parse(_ text: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: trimmingFraction(text)) ?? ISO8601DateFormatter().date(from: text)
    }

    private static func trimmingFraction(_ text: String) -> String {
        guard let dot = text.firstIndex(of: ".") else { return text }
        let digits = text[text.index(after: dot)...].prefix { $0.isNumber }
        let kept = String(digits.prefix(fractionDigits)).padding(toLength: fractionDigits, withPad: "0", startingAt: 0)
        return String(text[..<dot]) + "." + kept + text[digits.endIndex...]
    }
}
