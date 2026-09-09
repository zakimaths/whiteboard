import Foundation
import WhiteboardCore

let arguments = Array(CommandLine.arguments.dropFirst())
let includePDE = arguments.first == "--pde"
let paths = includePDE ? Array(arguments.dropFirst()) : arguments
guard paths.count == 2 else {
    fputs("Usage: WhiteboardSamples [--pde] <new-library-folder> <export-folder>\n",stderr); exit(1)
}
let root = URL(fileURLWithPath:paths[0],isDirectory:true)
let output = URL(fileURLWithPath:paths[1],isDirectory:true)
guard !FileManager.default.fileExists(atPath:root.path) else {
    fputs("Choose a new library folder; existing ideas will not be overwritten.\n",stderr); exit(1)
}
do {
    let library = try Library(root:root)
    try DemoContent.populate(library)
    if includePDE { try PDEExamples.installMissing(library) }
    try FileManager.default.createDirectory(at:output,withIntermediateDirectories:true)
    for item in try library.list() {
        let board = try library.load(item.url)
        let name = item.title.lowercased().replacingOccurrences(of:",",with:"").replacingOccurrences(of:" ",with:"-")
        try BoardRenderer.png(board,package:item.url).write(to:output.appendingPathComponent(name+".png"),options:.atomic)
        try BoardRenderer.pdf(board,package:item.url).write(to:output.appendingPathComponent(name+".pdf"),options:.atomic)
    }
    print("Created fictional editable \(includePDE ? "general and PDE" : "general") sample ideas and PNG/PDF exports.")
} catch { fputs("\(error.localizedDescription)\n",stderr); exit(1) }
