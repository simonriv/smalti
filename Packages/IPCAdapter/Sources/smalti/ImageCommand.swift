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
    let metrics = TerminalSize.metrics(of: STDOUT_FILENO)

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

    static func run(_ arguments: [String], in directory: String, terminal: any CommandTerminal) async -> Int32 {
        if arguments.first == "--help" || arguments.first == "-h" {
            terminal.write(usage)
            return 0
        }
        let listing: ImageListing
        do {
            listing = try ImageArguments.listing(arguments, currentDirectory: directory)
        } catch {
            guard case .missing(let path) = error else { return 1 }
            terminal.writeError("No existe: \(TerminalText.sanitized(path))\n")
            return 1
        }
        let output = await ShowImageGrid.render(listing, metrics: terminal.metrics, files: ImageIOImageFiles())
        terminal.write(output.stdout)
        if !output.stderr.isEmpty { terminal.writeError(output.stderr) }
        return output.exitCode
    }
}

enum ImageArgumentError: Error, Equatable {
    case missing(String)
}

/// From the arguments to the image paths: a folder gives its visible files (no recursion, subfolders left out), a file
/// gives itself, hidden or not. Files without an image extension count as skipped.
enum ImageArguments {
    static func listing(_ arguments: [String], currentDirectory: String) throws(ImageArgumentError) -> ImageListing {
        let given = arguments.isEmpty ? ["."] : arguments
        var images: [String] = []
        var skipped = 0
        for argument in given {
            let directory = URL(fileURLWithPath: currentDirectory, isDirectory: true)
            let path = URL(fileURLWithPath: argument, relativeTo: directory).standardizedFileURL.path
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) else {
                throw .missing(argument)
            }
            let files = isDirectory.boolValue ? visibleFiles(in: path) : [path]
            images += files.filter(ImageFileKind.isImage)
            skipped += files.count { !ImageFileKind.isImage($0) }
        }
        return ImageListing(source: given.joined(separator: " "), images: images, skipped: skipped)
    }

    private static func visibleFiles(in folder: String) -> [String] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder)) ?? []
        return names.filter { !$0.hasPrefix(".") }.map { "\(folder)/\($0)" }.filter { path in
            var isDirectory: ObjCBool = false
            return FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) && !isDirectory.boolValue
        }
    }
}
