import Foundation
import CoreGraphics
import ImageIO
import Darwin

public enum TeXKind: String, Codable { case latex, tikz }
public struct TeXSource: Codable, Equatable {
    public var kind: TeXKind
    public var code: String
    public init(kind: TeXKind, code: String) { self.kind = kind; self.code = code }
}
public struct TeXRender {
    public let pdf: Data
    public let png: Data
    public let width: Double
    public let height: Double
}
public enum TeXError: LocalizedError {
    case unavailable, invalid(String)
    public var errorDescription: String? {
        switch self {
        case .unavailable: return "LaTeX rendering needs a local TeX installation with pdflatex, standalone, amsmath and TikZ. Saved equations and diagrams can still be viewed without it."
        case .invalid(let detail): return detail
        }
    }
}

/// Explicit, on-demand rendering. Opening a saved board never executes its TeX source.
public enum TeXCompiler {
    public static var executable: URL? {
        ["/Library/TeX/texbin/pdflatex","/opt/homebrew/bin/pdflatex","/usr/local/bin/pdflatex"]
            .map {URL(fileURLWithPath:$0)}.first {FileManager.default.isExecutableFile(atPath:$0.path)}
    }
    public static func compile(_ source: TeXSource) throws -> TeXRender {
        guard let executable, FileManager.default.isExecutableFile(atPath:"/usr/bin/sandbox-exec") else { throw TeXError.unavailable }
        guard !source.code.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty, source.code.utf8.count <= 64*1024 else { throw TeXError.invalid("Enter an expression or diagram under 64 KB.") }
        guard let canonical = realpath(FileManager.default.temporaryDirectory.path,nil) else { throw BoardError.missingFile }
        let temporaryRoot = URL(fileURLWithPath:String(cString:canonical),isDirectory:true); free(canonical)
        let folder = temporaryRoot.appendingPathComponent("Whiteboard-TeX-"+UUID().uuidString,isDirectory:true)
        try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
        defer { try? FileManager.default.removeItem(at:folder) }
        let code = document(source)
        try code.write(to:folder.appendingPathComponent("drawing.tex"),atomically:true,encoding:.utf8)
        let engine = executable.resolvingSymlinksInPath()
        // TeX Live 2026 removed openin_any; filesystem isolation is enforced by the OS.
        func quoted(_ path: String) -> String { "\""+path.replacingOccurrences(of:"\\",with:"\\\\").replacingOccurrences(of:"\"",with:"\\\"")+"\"" }
        let execRules = ["/bin/bash",engine.path,executable.path].map {"(literal "+quoted($0)+")"}.joined(separator:" ")
        let readRules = ["/System","/usr/lib","/usr/share","/bin","/dev","/Library/TeX","/usr/local/texlive","/opt/homebrew/share/texmf-dist",engine.deletingLastPathComponent().path,folder.path].map {"(subpath "+quoted($0)+")"}.joined(separator:" ")
        let writeRule = "(subpath "+quoted(folder.path)+")"
        let profile = """
        (version 1)
        (allow default)
        (deny network*)
        (deny file-read-data)
        (deny file-write*)
        (deny process-exec)
        (allow process-fork)
        (allow process-exec \(execRules))
        (allow signal (target self))
        (allow sysctl-read)
        (allow mach-lookup)
        (allow file-read-metadata)
        (allow file-read-data (literal "/") \(readRules))
        (allow file-write* \(writeRule) (literal "/dev/null"))
        """
        let policy = folder.appendingPathComponent("render.sb"); try profile.write(to:policy,atomically:true,encoding:.utf8)
        let process = Process(); process.executableURL = URL(fileURLWithPath:"/usr/bin/sandbox-exec")
        process.currentDirectoryURL = folder
        // Resource limits apply only to this short-lived child. Source is a file, never shell text.
        process.arguments = ["-f",policy.path,"/bin/bash","-c","ulimit -t 12; ulimit -f 16384; exec \"$@\"","whiteboard-tex",executable.path,"-no-shell-escape","-no-parse-first-line","-no-mktex=tex","-no-mktex=tfm","-no-mktex=pk","-interaction=nonstopmode","-halt-on-error","-file-line-error","drawing.tex"]
        var environment = ProcessInfo.processInfo.environment
        environment["openin_any"] = "p"; environment["openout_any"] = "p"; environment["shell_escape"] = "f"
        environment["TEXMFOUTPUT"] = folder.path; environment["TEXMFVAR"] = folder.path
        environment["MKTEXFMT"] = "0"; environment["MKTEXPK"] = "0"
        process.environment = environment
        let log = folder.appendingPathComponent("engine-output.txt")
        FileManager.default.createFile(atPath:log.path,contents:nil)
        let handle = try FileHandle(forWritingTo:log); defer { try? handle.close() }
        process.standardOutput = handle; process.standardError = handle
        try process.run()
        let timeout = DispatchWorkItem { if process.isRunning { kill(process.processIdentifier,SIGKILL) } }
        DispatchQueue.global(qos:.utility).asyncAfter(deadline:.now()+20,execute:timeout)
        process.waitUntilExit(); timeout.cancel()
        guard process.terminationStatus == 0 else {
            let logText = (try? String(contentsOf:log,encoding:.utf8)) ?? ""
            let lines = logText.components(separatedBy:.newlines)
            let detail = lines.first(where: {$0.contains("drawing.tex:") || $0.hasPrefix("!")}) ?? (logText.isEmpty ? "The render did not finish. Check the source, installed packages or diagram complexity." : String(logText.suffix(400)))
            throw TeXError.invalid(String(detail.prefix(400)))
        }
        let pdf = try Data(contentsOf:folder.appendingPathComponent("drawing.pdf"))
        guard pdf.count <= 16*1024*1024, let provider = CGDataProvider(data:pdf as CFData), let document = CGPDFDocument(provider), document.numberOfPages == 1, let page = document.page(at:1) else { throw TeXError.invalid("Render a single equation or TikZ picture at a time.") }
        let rect = page.getBoxRect(.mediaBox)
        guard rect.width > 0, rect.height > 0, rect.width < 20_000, rect.height < 20_000 else { throw TeXError.invalid("This diagram is too large. Reduce its dimensions.") }
        let scale = min(3,4096/max(rect.width,rect.height),sqrt(8_000_000/(rect.width*rect.height)))
        let width = max(1,Int(ceil(rect.width*scale))), height = max(1,Int(ceil(rect.height*scale)))
        guard let context = CGContext(data:nil,width:width,height:height,bitsPerComponent:8,bytesPerRow:width*4,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue) else { throw TeXError.invalid("The preview could not be allocated.") }
        context.scaleBy(x:scale,y:scale); context.translateBy(x:-rect.minX,y:-rect.minY); context.drawPDFPage(page)
        let data = NSMutableData()
        guard let image = context.makeImage(), let destination = CGImageDestinationCreateWithData(data,"public.png" as CFString,1,nil) else { throw BoardError.invalidData }
        CGImageDestinationAddImage(destination,image,nil)
        guard CGImageDestinationFinalize(destination) else { throw BoardError.invalidData }
        return TeXRender(pdf:pdf,png:data as Data,width:rect.width,height:rect.height)
    }
    private static func document(_ source: TeXSource) -> String {
        let body: String, extra: String
        switch source.kind {
        case .latex:
            var code = source.code.trimmingCharacters(in:.whitespacesAndNewlines)
            for (start,end) in [("$$","$$"),("\\[","\\]"),("\\(","\\)"),("$","$")] {
                if code.hasPrefix(start), code.hasSuffix(end), code.count >= start.count+end.count { code = String(code.dropFirst(start.count).dropLast(end.count)); break }
            }
            body = "\\(\\displaystyle "+code+"\\)"; extra = ""
        case .tikz:
            body = source.code.contains("\\begin{tikzpicture}") ? source.code : "\\begin{tikzpicture}\n"+source.code+"\n\\end{tikzpicture}"
            extra = "\\usepackage{tikz}\n\\usetikzlibrary{arrows.meta,calc,positioning,shapes.geometric,decorations.pathreplacing}"
        }
        return "\\documentclass[border=6pt]{standalone}\n\\usepackage{amsmath,amssymb}\n"+extra+"\n\\begin{document}\n"+body+"\n\\end{document}\n"
    }
}
