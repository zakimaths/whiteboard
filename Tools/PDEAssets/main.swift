import Foundation
import WhiteboardCore

guard CommandLine.arguments.count == 2 else { fputs("Usage: WhiteboardPDEAssets <asset-output-folder>\n",stderr); exit(1) }
let output = URL(fileURLWithPath:CommandLine.arguments[1],isDirectory:true)
do {
    try FileManager.default.createDirectory(at:output,withIntermediateDirectories:true)
    for model in PDEExamples.models {
        for part in PDEExamples.parts {
            let name = model.key+"-"+part
            let source = try PDEExamples.source(name,kind:part == "diagram" ? .tikz : .latex)
            let rendered = try TeXCompiler.compile(source)
            try rendered.pdf.write(to:output.appendingPathComponent(name+".pdf"),options:.atomic)
            try rendered.png.write(to:output.appendingPathComponent(name+".png"),options:.atomic)
            print("Rendered \(name): \(Int(rendered.width)) × \(Int(rendered.height)) pt")
        }
    }
} catch { fputs("\(error.localizedDescription)\n",stderr); exit(1) }
