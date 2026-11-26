/// Where a text lives in a transcript (F9): the line (by file, inode, offset and length), the block in that line and
/// which field of it. The timeline keeps excerpts; copying reads the text again from here, whole.
public struct TextLocation: Hashable, Sendable {
    public let file: String
    /// A different inode means the file was rewritten and this place no longer holds the text.
    public let inode: UInt64
    public let offset: UInt64
    public let length: Int
    public let block: Int
    public let field: TextField

    public init(file: String, inode: UInt64, offset: UInt64, length: Int, block: Int, field: TextField) {
        self.file = file
        self.inode = inode
        self.offset = offset
        self.length = length
        self.block = block
        self.field = field
    }

    /// A key for the item that starts at this place ("<file>#<offset>.<block>").
    var key: String { "\(file)#\(offset).\(block)" }
}

/// Which part of a line's block holds the text.
public enum TextField: Hashable, Sendable {
    case text
    case toolInput
    case toolOutput
    case image
}
