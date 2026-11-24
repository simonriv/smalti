/// The files the preview shows (spec F5.5): those ImageIO paints, chosen by extension before touching the disk.
public enum ImageFileKind {
    static let extensions: Set<String> = ["png", "jpg", "jpeg", "gif", "heic", "heif", "webp", "tiff", "tif", "bmp"]

    /// True for a name with a stem and an admitted extension, in any case.
    public static func isImage(_ name: String) -> Bool {
        let file = name.split(separator: "/", omittingEmptySubsequences: false).last ?? ""
        guard let dot = file.lastIndex(of: "."), dot != file.startIndex else { return false }
        return extensions.contains(file[file.index(after: dot)...].lowercased())
    }
}
