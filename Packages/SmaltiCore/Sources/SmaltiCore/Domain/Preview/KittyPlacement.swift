import Foundation

/// The one dimension a thumbnail is sent with: the terminal works out the other from the image's proportion, so it is
/// never stretched (final review I1: with both, Ghostty fills the box exactly).
public enum KittyBox: Equatable, Sendable {
    case columns(Int)
    case rows(Int)

    var key: String {
        switch self {
        case .columns(let columns): "c=\(columns)"
        case .rows(let rows): "r=\(rows)"
        }
    }
}

/// One thumbnail as kitty graphics protocol commands (spec F5.5): transmit and display a PNG (`a=T,f=100`) scaled
/// to `box`, with the cursor left where it was (`C=1`) and no reply to the shell (`q=2`); the base64 payload goes in
/// chunks of at most 4096 bytes, `m=1` on all but the last.
public enum KittyPlacement {
    public static let chunkSize = 4096

    public static func sequences(png: Data, fitting box: KittyBox) -> [String] {
        let payload = Array(png.base64EncodedString().utf8)
        let chunks = stride(from: 0, to: payload.count, by: chunkSize).map { start in
            String(decoding: payload[start..<min(start + chunkSize, payload.count)], as: UTF8.self)
        }
        return chunks.enumerated().map { index, chunk in
            let more = index < chunks.count - 1 ? 1 : 0
            let keys = index == 0 ? "a=T,f=100,q=2,C=1,\(box.key),m=\(more)" : "m=\(more)"
            return "\u{1B}_G\(keys);\(chunk)\u{1B}\\"
        }
    }
}
