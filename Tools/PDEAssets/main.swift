import Foundation
import WhiteboardCore

let arguments = Array(CommandLine.arguments.dropFirst())
let checkOnly = arguments.first == "--check"
let paths = checkOnly ? Array(arguments.dropFirst()) : arguments
guard paths.count == 1 else { fputs("Usage: WhiteboardPDEAssets [--check] <asset-folder>\n",stderr); exit(1) }
let output = URL(fileURLWithPath:paths[0],isDirectory:true)
do {
    if !checkOnly { try FileManager.default.createDirectory(at:output,withIntermediateDirectories:true) }
    for model in PDEExamples.models {
        for part in PDEExamples.parts {
            let name = model.key+"-"+part
            let source = try PDEExamples.source(name,kind:part == "diagram" ? .tikz : .latex)
            let rendered = try TeXCompiler.compile(source)
            if checkOnly {
                let saved = try Data(contentsOf:output.appendingPathComponent(name+".png"))
                guard saved == rendered.png else {
                    throw NSError(domain:"WhiteboardPDEAssets",code:1,userInfo:[NSLocalizedDescriptionKey:"Rendered preview differs from \(name).png; regenerate the PDE assets."])
                }
                print("Verified \(name)")
            } else {
                try rendered.pdf.write(to:output.appendingPathComponent(name+".pdf"),options:.atomic)
                try rendered.png.write(to:output.appendingPathComponent(name+".png"),options:.atomic)
                print("Rendered \(name): \(Int(rendered.width)) × \(Int(rendered.height)) pt")
            }
        }
    }
} catch { fputs("\(error.localizedDescription)\n",stderr); exit(1) }
