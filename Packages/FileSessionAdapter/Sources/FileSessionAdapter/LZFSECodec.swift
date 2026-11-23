import Compression
import Foundation

/// LZFSE through Apple's Compression framework (the only importer of it in Smalti).
enum LZFSECodec {
    struct Failure: Error {
        let operation: String
    }

    static func compress(_ data: Data) throws(Failure) -> Data {
        guard !data.isEmpty else { return Data() }
        // LZFSE never needs more than the input plus a small header for incompressible data.
        let capacity = data.count + 4096
        return try run(data, capacity: capacity, operation: "compress") { destination, size, source, count in
            compression_encode_buffer(destination, size, source, count, nil, COMPRESSION_LZFSE)
        }
    }

    static func decompress(_ data: Data) throws(Failure) -> Data {
        guard !data.isEmpty else { return Data() }
        var capacity = max(data.count * 8, 1 << 16)
        // Grow until the output fits: a full buffer means it may have been truncated.
        while capacity <= 1 << 30 {
            let output = try run(data, capacity: capacity, operation: "decompress") {
                destination, size, source, count in
                compression_decode_buffer(destination, size, source, count, nil, COMPRESSION_LZFSE)
            }
            if output.count < capacity { return output }
            capacity *= 4
        }
        throw Failure(operation: "decompress: output larger than 1 GB")
    }

    private static func run(
        _ data: Data, capacity: Int, operation: String,
        _ codec: (UnsafeMutablePointer<UInt8>, Int, UnsafePointer<UInt8>, Int) -> Int
    ) throws(Failure) -> Data {
        var output = Data(count: capacity)
        let written = output.withUnsafeMutableBytes { destination in
            data.withUnsafeBytes { source in
                // Safe: both buffers come from non-empty Data values, so their base addresses exist.
                guard let destination = destination.bindMemory(to: UInt8.self).baseAddress,
                    let source = source.bindMemory(to: UInt8.self).baseAddress
                else { return 0 }
                return codec(destination, capacity, source, data.count)
            }
        }
        guard written > 0 else { throw Failure(operation: operation) }
        return output.prefix(written)
    }
}
