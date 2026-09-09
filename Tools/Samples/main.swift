import Foundation
import WhiteboardCore

guard CommandLine.arguments.count == 3 else {
    fputs("Usage: WhiteboardSamples <new-library-folder> <export-folder>\n",stderr); exit(1)
}
let root = URL(fileURLWithPath:CommandLine.arguments[1],isDirectory:true)
let output = URL(fileURLWithPath:CommandLine.arguments[2],isDirectory:true)
guard !FileManager.default.fileExists(atPath:root.path) else {
    fputs("Choose a new library folder; existing ideas will not be overwritten.\n",stderr); exit(1)
}
do {
    let library = try Library(root:root)
    try DemoContent.populate(library)
    try FileManager.default.createDirectory(at:output,withIntermediateDirectories:true)
    for item in try library.list() {
        let board = try library.load(item.url)
        let name = item.title.lowercased().replacingOccurrences(of:",",with:"").replacingOccurrences(of:" ",with:"-")
        try BoardRenderer.png(board,package:item.url).write(to:output.appendingPathComponent(name+".png"),options:.atomic)
        try BoardRenderer.pdf(board,package:item.url).write(to:output.appendingPathComponent(name+".pdf"),options:.atomic)
    }
    print("Created fictional editable sample ideas and PNG/PDF exports.")
} catch { fputs("\(error.localizedDescription)\n",stderr); exit(1) }
