import Foundation
import ImageIOAdapter
import SmaltiCore

/// Where `smalti img` writes: its output, its errors and, when the output is a terminal that reports pixel sizes,
/// the size of a cell.
protocol CommandTerminal {
    var metrics: CellMetrics? { get }
    func write(_ text: String)
    func writeError(_ text: String)
}

/// The process's own standard output and error.
struct StandardTerminal: CommandTerminal {
    let metrics = TerminalSize.metrics(of: STDOUT_FILENO, environment: ProcessInfo.processInfo.environment)

    func write(_ text: String) { FileHandle.standardOutput.write(Data(text.utf8)) }
    func writeError(_ text: String) { FileHandle.standardError.write(Data(text.utf8)) }
}

/// `smalti img [carpeta | archivos…]` (spec F5.5): the images of a folder (or the files named) as a thumbnail grid.
enum ImageCommand {
    static let usage = """
        uso: smalti img [carpeta | archivos…]
        Muestra las imágenes en una cuadrícula de miniaturas (sin argumentos, las de la carpeta actual).
        Fuera de una terminal escribe solo los nombres y los tamaños.

        """

    /// Describing reads every file's header: past this many, a terminal is told why it waits.
    static let announcedFileCount = 500

    static func run(_ arguments: [String], in directory: String, terminal: any CommandTerminal) async -> Int32 {
        let options = arguments.prefix { $0 != "--" }
        if options.contains("--help") || options.contains("-h") {
            terminal.write(usage)
            return 0
        }
        let listing: ImageListing
        do {
            listing = try ImageArguments.listing(arguments, currentDirectory: directory)
        } catch {
            terminal.writeError(error.message)
            return 1
        }
        if terminal.metrics != nil, listing.images.count > announcedFileCount {
            terminal.writeError("Leyendo \(listing.images.count) archivos…\n")
        }
        await ShowImageGrid.render(listing, to: TerminalSink(terminal), files: ImageIOImageFiles())
        return 0
    }
}

/// The grid's rows go straight to the terminal as they are ready.
final class TerminalSink: GridSink, @unchecked Sendable {
    // Unchecked: the CLI writes from one task at a time, in order.
    private let terminal: any CommandTerminal

    init(_ terminal: any CommandTerminal) {
        self.terminal = terminal
    }

    var metrics: CellMetrics? { terminal.metrics }

    func write(_ text: String) { terminal.write(text) }
}

enum ImageArgumentError: Error, Equatable {
    case missing(String)
    case unreadable(String, reason: String)

    /// What the user reads on stderr, with the argument as written.
    var message: String {
        switch self {
        case .missing(let path): "No existe: \(TerminalText.sanitized(path))\n"
        case .unreadable(let path, _): "No se pudo leer: \(TerminalText.sanitized(path))\n"
        }
    }
}

/// From the arguments to the image paths: a folder gives its visible files (no recursion, subfolders left out), a file
/// gives itself, hidden or not. Files without an image extension count as skipped.
enum ImageArguments {
    static func listing(_ arguments: [String], currentDirectory: String) throws(ImageArgumentError) -> ImageListing {
        let paths = arguments.filter { $0 != "--" }
        let given = paths.isEmpty ? ["."] : paths
        var images: [String] = []
        var skipped = 0
        for argument in given {
            let entries = try entries(of: argument, in: currentDirectory)
            images += entries.filter(ImageFileKind.isImage)
            skipped += entries.count { !ImageFileKind.isImage($0) }
        }
        var seen = Set<String>()
        let unique = images.filter { seen.insert($0).inserted }
        return ImageListing(
            source: given.joined(separator: " "), images: unique, skipped: skipped, texts: .spanish /* T8 */)
    }

    /// The argument's files: a folder's visible entries that are not folders (a broken link included, so it counts
    /// as skipped), or the file itself.
    private static func entries(of argument: String, in currentDirectory: String) throws(ImageArgumentError)
        -> [String]
    {
        let directory = URL(fileURLWithPath: currentDirectory, isDirectory: true)
        let path = URL(fileURLWithPath: argument, relativeTo: directory).standardizedFileURL.path
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) else {
            throw .missing(argument)
        }
        guard isDirectory.boolValue else { return [path] }
        let names: [String]
        do {
            names = try FileManager.default.contentsOfDirectory(atPath: path)
        } catch {
            throw .unreadable(argument, reason: error.localizedDescription)
        }
        return names.filter { !$0.hasPrefix(".") }.map { "\(path)/\($0)" }.filter { entry in
            var isFolder: ObjCBool = false
            return !FileManager.default.fileExists(atPath: entry, isDirectory: &isFolder) || !isFolder.boolValue
        }
    }
}
