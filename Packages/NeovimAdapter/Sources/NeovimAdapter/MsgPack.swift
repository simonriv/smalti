import Foundation

/// The MessagePack values Neovim's RPC uses (spec: msgpack.org). Extension types carry Neovim's handles.
enum MsgPackValue: Hashable, Sendable {
    case `nil`
    case bool(Bool)
    case int(Int64)
    case double(Double)
    case string(String)
    case binary(Data)
    case array([MsgPackValue])
    case map([MsgPackValue: MsgPackValue])
    case ext(Int8, Data)
}

enum MsgPackError: Error, Equatable {
    /// More bytes are needed: the message is still arriving.
    case incomplete
    case unsupported(UInt8)
}

enum MsgPack {
    static func encode(_ value: MsgPackValue) -> Data {
        var data = Data()
        write(value, into: &data)
        return data
    }

    /// The first value in `bytes` and how many bytes it took.
    static func decode(_ bytes: Data) throws(MsgPackError) -> (value: MsgPackValue, count: Int) {
        var reader = Reader(bytes: [UInt8](bytes))
        let value = try reader.value()
        return (value, reader.offset)
    }

    private static func write(_ value: MsgPackValue, into data: inout Data) {
        switch value {
        case .nil: data.append(0xC0)
        case .bool(let flag): data.append(flag ? 0xC3 : 0xC2)
        case .int(let number): writeInt(number, into: &data)
        case .double(let number):
            data.append(0xCB)
            append(number.bitPattern, bytes: 8, into: &data)
        case .string(let text): writeString(text, into: &data)
        case .binary(let bytes):
            data.append(0xC6)
            append(UInt64(bytes.count), bytes: 4, into: &data)
            data.append(bytes)
        case .array(let items):
            writeLength(items.count, small: 0x90, medium: 0xDC, large: 0xDD, into: &data)
            items.forEach { write($0, into: &data) }
        case .map(let pairs):
            writeLength(pairs.count, small: 0x80, medium: 0xDE, large: 0xDF, into: &data)
            for (key, item) in pairs.sorted(by: { "\($0.key)" < "\($1.key)" }) {
                write(key, into: &data)
                write(item, into: &data)
            }
        case .ext(let type, let bytes):
            data.append(0xC7)
            data.append(UInt8(bytes.count & 0xFF))
            data.append(UInt8(bitPattern: type))
            data.append(bytes)
        }
    }

    private static func writeInt(_ number: Int64, into data: inout Data) {
        switch number {
        case 0...0x7F: data.append(UInt8(number))
        case -32..<0: data.append(UInt8(bitPattern: Int8(number)))
        default:
            data.append(0xD3)
            append(UInt64(bitPattern: number), bytes: 8, into: &data)
        }
    }

    private static func writeString(_ text: String, into data: inout Data) {
        let bytes = Data(text.utf8)
        if bytes.count < 32 {
            data.append(0xA0 | UInt8(bytes.count))
        } else {
            data.append(0xDB)
            append(UInt64(bytes.count), bytes: 4, into: &data)
        }
        data.append(bytes)
    }

    private static func writeLength(_ count: Int, small: UInt8, medium: UInt8, large: UInt8, into data: inout Data) {
        if count < 16 {
            data.append(small | UInt8(count))
        } else if count <= 0xFFFF {
            data.append(medium)
            append(UInt64(count), bytes: 2, into: &data)
        } else {
            data.append(large)
            append(UInt64(count), bytes: 4, into: &data)
        }
    }

    private static func append(_ value: UInt64, bytes: Int, into data: inout Data) {
        for shift in stride(from: (bytes - 1) * 8, through: 0, by: -8) {
            data.append(UInt8((value >> UInt64(shift)) & 0xFF))
        }
    }

    struct Reader {
        let bytes: [UInt8]
        var offset = 0

        mutating func value() throws(MsgPackError) -> MsgPackValue {
            let head = try byte()
            switch head {
            case 0x00...0x7F: return .int(Int64(head))
            case 0xE0...0xFF: return .int(Int64(Int8(bitPattern: head)))
            case 0x80...0x8F: return try map(Int(head & 0x0F))
            case 0x90...0x9F: return try array(Int(head & 0x0F))
            case 0xA0...0xBF: return try string(Int(head & 0x1F))
            case 0xC0: return .nil
            case 0xC2: return .bool(false)
            case 0xC3: return .bool(true)
            default: return try sized(head)
            }
        }

        private mutating func sized(_ head: UInt8) throws(MsgPackError) -> MsgPackValue {
            switch head {
            case 0xC4, 0xC5, 0xC6: return .binary(Data(try take(Int(try unsigned([1, 2, 4][Int(head - 0xC4)])))))
            case 0xC7, 0xC8, 0xC9:
                let length = Int(try unsigned([1, 2, 4][Int(head - 0xC7)]))
                let type = Int8(bitPattern: try byte())
                return .ext(type, Data(try take(length)))
            case 0xCA: return .double(Double(Float(bitPattern: UInt32(try unsigned(4)))))
            case 0xCB: return .double(Double(bitPattern: try unsigned(8)))
            case 0xCC, 0xCD, 0xCE, 0xCF: return .int(Int64(truncatingIfNeeded: try unsigned(1 << Int(head - 0xCC))))
            case 0xD0, 0xD1, 0xD2, 0xD3: return .int(try signed(1 << Int(head - 0xD0)))
            case 0xD4, 0xD5, 0xD6, 0xD7, 0xD8:
                let type = Int8(bitPattern: try byte())
                return .ext(type, Data(try take(1 << Int(head - 0xD4))))
            case 0xD9, 0xDA, 0xDB: return try string(Int(try unsigned(1 << Int(head - 0xD9))))
            case 0xDC, 0xDD: return try array(Int(try unsigned(head == 0xDC ? 2 : 4)))
            case 0xDE, 0xDF: return try map(Int(try unsigned(head == 0xDE ? 2 : 4)))
            default: throw .unsupported(head)
            }
        }

        private mutating func byte() throws(MsgPackError) -> UInt8 {
            guard offset < bytes.count else { throw .incomplete }
            defer { offset += 1 }
            return bytes[offset]
        }

        private mutating func take(_ count: Int) throws(MsgPackError) -> ArraySlice<UInt8> {
            guard count >= 0, offset + count <= bytes.count else { throw .incomplete }
            defer { offset += count }
            return bytes[offset..<offset + count]
        }

        private mutating func unsigned(_ count: Int) throws(MsgPackError) -> UInt64 {
            try take(count).reduce(0) { $0 << 8 | UInt64($1) }
        }

        private mutating func signed(_ count: Int) throws(MsgPackError) -> Int64 {
            let raw = try unsigned(count)
            let shift = UInt64(64 - count * 8)
            return Int64(bitPattern: raw << shift) >> Int64(shift)
        }

        private mutating func string(_ count: Int) throws(MsgPackError) -> MsgPackValue {
            .string(String(decoding: try take(count), as: UTF8.self))
        }

        private mutating func array(_ count: Int) throws(MsgPackError) -> MsgPackValue {
            var items: [MsgPackValue] = []
            for _ in 0..<count { items.append(try value()) }
            return .array(items)
        }

        private mutating func map(_ count: Int) throws(MsgPackError) -> MsgPackValue {
            var pairs: [MsgPackValue: MsgPackValue] = [:]
            for _ in 0..<count {
                let key = try value()
                pairs[key] = try value()
            }
            return .map(pairs)
        }
    }
}
