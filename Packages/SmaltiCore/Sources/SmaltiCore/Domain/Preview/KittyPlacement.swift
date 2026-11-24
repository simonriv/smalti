import Foundation

/// One thumbnail as kitty graphics protocol commands (spec F5.5): transmit and display a PNG (`a=T,f=100`) scaled
/// into `columns × rows` cells, with the cursor left where it was (`C=1`) and no reply to the shell (`q=2`); the
/// base64 payload goes in chunks of at most 4096 bytes, `m=1` on all but the last.
public enum KittyPlacement {
    public static let chunkSize = 4096

    public static func sequences(png: Data, columns: Int, rows: Int) -> [String] {
        let payload = Array(png.base64EncodedString().utf8)
        let chunks = stride(from: 0, to: payload.count, by: chunkSize).map { start in
            String(decoding: payload[start..<min(start + chunkSize, payload.count)], as: UTF8.self)
        }
        return chunks.enumerated().map { index, chunk in
            let more = index < chunks.count - 1 ? 1 : 0
            let keys = index == 0 ? "a=T,f=100,q=2,C=1,c=\(columns),r=\(rows),m=\(more)" : "m=\(more)"
            return "\u{1B}_G\(keys);\(chunk)\u{1B}\\"
        }
    }
}
