import Foundation
import CoreGraphics
import ImageIO
import WhiteboardCore

var passed = 0, failed = 0
func check(_ name: String, _ body: () throws -> Void) {
    do { try body(); print("PASS \(name)"); passed += 1 }
    catch { print("FAIL \(name): \(error)"); failed += 1 }
}
struct Failure: Error { let message: String }
func expect(_ condition: @autoclosure () throws -> Bool, _ message: String = "Expectation failed") throws {
    if try !condition() { throw Failure(message: message) }
}
func rejects(_ body: () throws -> Void) throws {
    do { try body() } catch { return }
    throw Failure(message: "Expected rejection")
}
func temporaryLibrary(_ action: (Library) throws -> Void) throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("Whiteboard-checks-"+UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    try action(Library(root: root))
}

check("Zoom keeps the point under the cursor fixed, including limits") {
    var view = Viewport(); view.origin = Point(-600,12000)
    let anchor = Point(721,403), before = view.world(Point(721,403))
    for zoom in [0.01,0.5,3,100,1] {
        view.zoom(to: zoom, at: anchor)
        let after = view.world(anchor)
        try expect(abs(before.x-after.x) < 0.000001 && abs(before.y-after.y) < 0.000001)
        try expect((0.15...4).contains(view.zoom))
    }
}
check("Image movement preserves attached ink and leaves other ink alone") {
    var board = Board(); let image = BoardImage(asset:"a.png",frame:Rect(10,20,100,100))
    board.images = [image]
    board.ink = [Ink(points:[Point(12,25)], imageID:image.id), Ink(points:[Point(100,500)])]
    board.moveImage(id:image.id,by:Point(30,-10))
    try expect(board.ink[0].points[0] == Point(42,15)); try expect(board.ink[1].points[0] == Point(100,500))
    board.images[0].locked = true; board.moveImage(id:image.id,by:Point(10,10))
    try expect(board.ink[0].points[0] == Point(42,15))
}
check("Eraser tests line segments, not just bounding boxes") {
    let line = Ink(points:[Point(0,0),Point(100,100)])
    try expect(line.hits(Point(50,51),radius:3)); try expect(!line.hits(Point(10,90),radius:3))
    try expect(!Ink(points:[]).hits(Point(0,0),radius:3))
}
check("Save and reopen preserve all editable content and viewport") {
    try temporaryLibrary { library in
        var board = Board(); board.ink = [Ink(points:[Point(-20,40),Point(1,23000)])]
        board.texts = [BoardText(text:"Idea ∑ café",origin:Point(4,8))]
        board.viewport.origin = Point(-100,22000); board.viewport.zoom = 0.3
        let url = try library.create(name:"Thought",board:board)
        let restored = try library.load(url); try expect(restored == board)
    }
}
check("Duplicate names never overwrite existing boards") {
    try temporaryLibrary { library in
        let first = try library.create(name:"Same"), second = try library.create(name:"Same")
        try expect(first != second); try expect(try library.list().count == 2)
    }
}
check("Repeated autosaves do not conflict with the app's own atomic writes") {
    try temporaryLibrary { library in
        let url = try library.create(); var board = try library.load(url)
        for i in 0..<25 {
            board.texts.append(BoardText(text:"Edit \(i)",origin:Point(Double(i),0)))
            try library.save(board,at:url)
        }
        try expect(try library.load(url) == board)
    }
}
check("Filename sanitisation cannot escape the chosen folder") {
    try temporaryLibrary { library in
        let url = try library.create(name:"../../outside\n/thing")
        try expect(url.deletingLastPathComponent() == library.folder(.unfinished))
    }
}
check("Finished status is represented by the real folder") {
    try temporaryLibrary { library in
        let url = try library.create(name:"My thought")
        let moved = try library.move(url,to:.finished)
        try expect(!FileManager.default.fileExists(atPath:url.path))
        try expect(try library.list().first?.status == .finished)
        var board = try library.load(moved); board.texts.append(BoardText(text:"Continue",origin:Point(0,0)))
        try library.save(board,at:moved)
        let reopened = try library.move(moved,to:.unfinished)
        try expect(try library.load(reopened) == board)
    }
}
check("External modification prevents overwrite") {
    try temporaryLibrary { library in
        let url = try library.create(); let original = try library.load(url)
        let file = url.appendingPathComponent("board.json")
        var external = original; external.recognisedText = "External edit"
        try JSONEncoder().encode(external).write(to:file,options:.atomic)
        try FileManager.default.setAttributes([.modificationDate:Date(timeIntervalSinceNow:30)],ofItemAtPath:file.path)
        try rejects { try library.save(original,at:url) }
        try expect(try library.load(url).recognisedText == "External edit")
    }
}
check("Externally removed board is not silently recreated") {
    try temporaryLibrary { library in
        let url = try library.create(); try FileManager.default.removeItem(at:url)
        try rejects { try library.save(Board(),at:url) }
        try expect(!FileManager.default.fileExists(atPath:url.path))
    }
}
check("Previous revision survives a normal autosave") {
    try temporaryLibrary { library in
        let original = Board(), url = try library.create(board:original)
        var board = original; board.texts = [BoardText(text:"New",origin:Point(0,0))]
        try library.save(board,at:url)
        let previous = try JSONDecoder().decode(Board.self,from:Data(contentsOf:url.appendingPathComponent("previous.json")))
        try expect(previous == original); try expect(try library.load(url) == board)
    }
}
check("Invalid versions, asset paths and duplicate object IDs are rejected") {
    var board = Board(); board.version = 999; try rejects { _ = try board.validated() }
    board = Board(); board.images = [BoardImage(asset:"../private.png",frame:Rect(0,0,10,10))]
    try rejects { _ = try board.validated() }
    board = Board(); let ink = Ink(points:[Point(0,0)]); board.ink = [ink,ink]
    try rejects { _ = try board.validated() }
}
check("Copies embed imported images and survive removal of original board") {
    try temporaryLibrary { library in
        let original = try library.create(); let data = Data([1,2,3,4])
        let asset = try library.importAsset(data:data,extension:"png",to:original)
        var board = Board(); board.images = [BoardImage(asset:asset,frame:Rect(1,2,50,40))]
        let copy = try library.copy(board,from:original,name:"Copy")
        try FileManager.default.removeItem(at:original)
        try expect(try Data(contentsOf:copy.appendingPathComponent("assets").appendingPathComponent(asset)) == data)
        try expect(try library.load(copy) == board)
    }
}
check("Failed image copy leaves no broken shelf item") {
    try temporaryLibrary { library in
        let original = try library.create(); var board = Board()
        board.images = [BoardImage(asset:"missing.png",frame:Rect(0,0,10,10))]
        try rejects { _ = try library.copy(board,from:original,name:"Broken") }
        try expect(try library.list().count == 1)
    }
}
check("Visible screenshot previews share a bounded pixel budget") {
    for count in 1...PreviewBudget.maximumVisibleImages {
        let side = PreviewBudget.maxPixelSize(visibleCount:count)
        try expect(side * side * 16 * count <= PreviewBudget.bytes)
        try expect(side > 0 && side <= 1536)
    }
}
check("Resizing a screenshot transforms attached ink and survives save/reopen") {
    try temporaryLibrary { library in
        var board = Board(); let image = BoardImage(asset:"a.png",frame:Rect(10,20,100,200)); board.images = [image]
        board.ink = [Ink(points:[Point(60,120)],width:3,imageID:image.id),Ink(points:[Point(1000,1000)])]
        board.resizeImage(id:image.id,width:200)
        try expect(board.images[0].frame == Rect(10,20,200,400)); try expect(board.ink[0].points == [Point(110,220)])
        try expect(board.ink[0].width == 6); try expect(board.ink[1].points == [Point(1000,1000)])
        let url = try library.create(board:board); try expect(try library.load(url) == board)
        board.images[0].locked = true; let before = board; board.resizeImage(id:image.id,width:300); try expect(board == before)
    }
}
check("Duplicate remaps attachments; fresh attempts leave the original intact") {
    var board = Board(); let image = BoardImage(asset:"a.png",frame:Rect(10,20,100,200)); board.images = [image]
    board.ink = [Ink(points:[Point(50,60)],imageID:image.id)]
    let selection = board.duplicate([image.id]); try expect(selection.count == 2)
    try expect(board.images[0] == image); try expect(board.ink[1].imageID == board.images[1].id)
    try expect(board.ink[1].points == [Point(86,96)])
    _ = board.duplicate([image.id],withAnnotations:false); try expect(board.images.count == 3 && board.ink.count == 2)
    _ = try board.validated()
    let inkOnly = board.selection([board.ink[0].id]); try expect(inkOnly.images.isEmpty && inkOnly.ink[0].imageID == nil)
}
check("Recovery copies the last good revision even when the current file is corrupt") {
    try temporaryLibrary { library in
        var original = Board(); original.texts = [BoardText(text:"Keep this thought",origin:Point(30,40))]
        let source = try library.create(board:original); var next = original; next.texts.removeAll(); try library.save(next,at:source)
        let file = source.appendingPathComponent("board.json"), corrupt = Data("corrupt".utf8); try corrupt.write(to:file)
        let recovered = try library.recoverPrevious(source)
        try expect(try library.load(recovered).texts == original.texts)
        try expect(try Data(contentsOf:file) == corrupt)
    }
}
check("Invalid saves leave current and previous files untouched") {
    try temporaryLibrary { library in
        let url = try library.create(); let file = url.appendingPathComponent("board.json"), before = try Data(contentsOf:file)
        var bad = Board(); bad.images = [BoardImage(asset:"../outside.png",frame:Rect(0,0,1,1))]
        try rejects { try library.save(bad,at:url) }; try expect(try Data(contentsOf:file) == before)
        try rejects { _ = try library.create(name:"Bad",board:bad) }; try expect(try library.list().count == 1)
    }
}
check("PNG and PDF contain whole content, including offscreen text and source images") {
    try temporaryLibrary { library in
        var board = Board(); board.texts = [BoardText(text:"A thought worth keeping",origin:Point(80,-130)),BoardText(text:"x² + y² = r²",origin:Point(80,200))]
        board.ink = [Ink(points:[Point(80,100),Point(260,130)],colour:"blue",width:4)]
        let source = try library.create()
        let bitmap = CGContext(data:nil,width:80,height:80,bitsPerComponent:8,bytesPerRow:320,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
        bitmap.setFillColor(CGColor(red:0.1,green:0.6,blue:0.3,alpha:1)); bitmap.fill(CGRect(x:0,y:0,width:80,height:80))
        bitmap.setFillColor(CGColor(red:1,green:0.2,blue:0.2,alpha:1)); bitmap.fill(CGRect(x:0,y:40,width:80,height:40))
        let pixels = NSMutableData(), destination = CGImageDestinationCreateWithData(pixels,"public.png" as CFString,1,nil)!
        CGImageDestinationAddImage(destination,bitmap.makeImage()!,nil); try expect(CGImageDestinationFinalize(destination))
        let asset = try library.importAsset(data:pixels as Data,extension:"png",to:source)
        board.images = [BoardImage(asset:asset,frame:Rect(80,-70,160,160))]
        board.viewport.origin = Point(10000,10000)
        let png = try BoardRenderer.png(board,package:source), pdf = try BoardRenderer.pdf(board,package:source)
        let imageSource = CGImageSourceCreateWithData(png as CFData,nil)!, image = CGImageSourceCreateImageAtIndex(imageSource,0,nil)!
        try expect(image.width > 300 && image.height > 600)
        let document = CGPDFDocument(CGDataProvider(data:pdf as CFData)!)!; try expect(document.numberOfPages == 1)
        if let output = ProcessInfo.processInfo.environment["WHITEBOARD_TEST_ARTIFACTS"] {
            let folder = URL(fileURLWithPath:output); try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
            try png.write(to:folder.appendingPathComponent("export-check.png")); try pdf.write(to:folder.appendingPathComponent("export-check.pdf"))
        }
        try FileManager.default.removeItem(at:source.appendingPathComponent("assets").appendingPathComponent(asset))
        try rejects { _ = try BoardRenderer.png(board,package:source) }
    }
}
if ProcessInfo.processInfo.environment["WHITEBOARD_TEX_CHECKS"] == "1" {
    check("Real LaTeX rendering preserves editable source and vector assets through copy/reopen") {
        try temporaryLibrary { library in
            let source = TeXSource(kind:.latex,code:#"x = \frac{-b \pm \sqrt{b^2-4ac}}{2a}"#)
            let render = try TeXCompiler.compile(source)
            try expect(render.pdf.count > 100 && render.png.count > 100 && render.width > render.height)
            let url = try library.create(); var board = Board()
            var item = BoardImage(asset:try library.importAsset(data:render.png,extension:"png",to:url),frame:Rect(0,0,render.width*2,render.height*2))
            item.tex = source; item.vectorAsset = try library.importAsset(data:render.pdf,extension:"pdf",to:url); board.images = [item]
            try library.save(board,at:url); let copy = try library.copy(board,from:url,name:"Equation copy")
            try FileManager.default.removeItem(at:url)
            try expect(try library.load(copy).images[0].tex == source)
            let pdf = try BoardRenderer.pdf(board,package:copy); try expect(pdf.count > 100)
            if let output = ProcessInfo.processInfo.environment["WHITEBOARD_TEST_ARTIFACTS"] {
                let folder = URL(fileURLWithPath:output); try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
                try BoardRenderer.png(board,package:copy).write(to:folder.appendingPathComponent("latex-check.png"))
                try pdf.write(to:folder.appendingPathComponent("latex-check.pdf"))
            }
        }
    }
    check("Real TikZ diagram renders without a persistent engine") {
        let source = TeXSource(kind:.tikz,code:#"\draw[blue,thick,->] (0,0) -- (3,1) node[right] {$v$};"#)
        let render = try TeXCompiler.compile(source)
        try expect(render.width > 50 && render.height > 10)
        if let output = ProcessInfo.processInfo.environment["WHITEBOARD_TEST_ARTIFACTS"] { try render.png.write(to:URL(fileURLWithPath:output).appendingPathComponent("tikz-check.png")) }
    }
    check("Invalid TeX fails and the compiler cannot read outside its isolated workspace") {
        try rejects { _ = try TeXCompiler.compile(TeXSource(kind:.latex,code:#"\notARealMathCommand{"#)) }
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("Whiteboard-private-check-"+UUID().uuidString+".tex")
        try "private fixture".write(to:file,atomically:true,encoding:.utf8); defer {try? FileManager.default.removeItem(at:file)}
        try rejects { _ = try TeXCompiler.compile(TeXSource(kind:.latex,code:"\\input{"+file.path+"}")) }
    }
} else { print("NOTE LaTeX/TikZ integration checks require WHITEBOARD_TEX_CHECKS=1 and local TeX packages.") }
print("\n\(passed) passed, \(failed) failed")
exit(failed == 0 ? 0 : 1)
