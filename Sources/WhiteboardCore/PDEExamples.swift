import Foundation
import CoreGraphics

public struct PDEModel {
    public let key: String
    public let title: String
    public let subtitle: String
    public let interpretation: String
}

/// Original worked examples. Pre-rendered vectors open without running a TeX engine.
public enum PDEExamples {
    public static let models = [
        PDEModel(key:"heat",title:"Heat diffusion — modes and decay",subtitle:"A uniform rod, zero relative-temperature boundary values and two initial Fourier modes.",interpretation:"The third mode has nine times the decay rate. Check the boundary values and energy dissipation."),
        PDEModel(key:"wave",title:"Wave motion — a fixed string",subtitle:"An undamped string released from its first mode with zero initial velocity.",interpretation:"A standing wave exchanges kinetic and strain energy. Its total energy remains constant."),
        PDEModel(key:"poisson",title:"Poisson — a field on the unit square",subtitle:"A manufactured exact solution, homogeneous Dirichlet data and a five-point discretisation.",interpretation:"Distinguish the algebraic residual from discretisation error; check boundary values and grid convergence.")
    ]
    public static let parts = ["model","solution","diagram","numerics"]
    public static var resourceDirectory: URL {
        if let folder = Bundle.main.resourceURL?.appendingPathComponent("PDE"), FileManager.default.fileExists(atPath:folder.path) { return folder }
        return Bundle.module.resourceURL!.appendingPathComponent("PDE")
    }
    public static func source(_ name: String, kind: TeXKind) throws -> TeXSource {
        TeXSource(kind:kind,code:try String(contentsOf:resourceDirectory.appendingPathComponent(name+".tex"),encoding:.utf8))
    }
    @discardableResult public static func installMissing(_ library: Library) throws -> [URL] {
        let marker = library.root.appendingPathComponent(".pde-examples-v1")
        if FileManager.default.fileExists(atPath:marker.path) { return [] }
        let existing = try library.list(); var added: [URL] = []
        for model in models where !existing.contains(where: {$0.title == model.title}) {
            let url = try library.create(name:model.title)
            do {
                var board = Board(); board.background = "paper"; board.viewport.zoom = 0.8
                func text(_ value: String, _ x: Double, _ y: Double, _ size: Double = 20) -> BoardText {
                    var item = BoardText(text:value,origin:Point(x,y)); item.size = size; return item
                }
                board.texts = [text(model.title,180,220,36),text(model.subtitle,180,277,20),text("01 / MODEL + CONDITIONS",180,345,15),text("02 / EXACT SOLUTION + CHECK",870,345,15)]
                var lowerY = 750.0
                for part in parts {
                    let name = model.key+"-"+part
                    let pdf = try Data(contentsOf:resourceDirectory.appendingPathComponent(name+".pdf"))
                    let png = try Data(contentsOf:resourceDirectory.appendingPathComponent(name+".png"))
                    guard let document = CGPDFDocument(CGDataProvider(data:pdf as CFData)!), let page = document.page(at:1) else { throw BoardError.invalidData }
                    let bounds = page.getBoxRect(.mediaBox)
                    let width = part == "diagram" ? 640.0 : min(610.0,bounds.width*2)
                    let height = width*bounds.height/bounds.width
                    let x = part == "model" || part == "diagram" ? 180.0 : 870.0
                    let y = part == "model" || part == "solution" ? 380.0 : lowerY+40
                    if part == "model" || part == "solution" { lowerY = max(lowerY,y+height+70) }
                    var image = BoardImage(asset:try library.importAsset(data:png,extension:"png",to:url),frame:Rect(x,y,width,height))
                    image.vectorAsset = try library.importAsset(data:pdf,extension:"pdf",to:url)
                    image.tex = try source(name,kind:part == "diagram" ? .tikz : .latex); board.images.append(image)
                }
                board.texts += [text("03 / GEOMETRY + BEHAVIOUR",180,lowerY,15),text("04 / DISCRETISATION",870,lowerY,15)]
                let bottom = board.images.map {$0.frame.y+$0.frame.height}.max()!+50
                board.texts += [text(model.interpretation,180,bottom,19),text("Select and double-click any equation or diagram to edit its source. Scroll to work below.",180,bottom+40,18)]
                try library.save(board,at:url); added.append(url)
            } catch { try? FileManager.default.removeItem(at:url); throw error }
        }
        try Data("1\n".utf8).write(to:marker,options:.atomic)
        return added
    }
}
