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
check("Shape constraints work in every drag direction and arrows have stable heads") {
    let start = Point(100,100)
    for end in [Point(300,150),Point(-100,150),Point(-100,-50),Point(300,-50)] {
        let line = DrawingShape.line.points(from:start,to:end,constrained:true)
        let dx = line[1].x-start.x, dy = line[1].y-start.y
        try expect(abs(dx) < 0.000001 || abs(dy) < 0.000001 || abs(abs(dx)-abs(dy)) < 0.000001)
        let rectangle = DrawingShape.rectangle.points(from:start,to:end,constrained:true)
        try expect(rectangle.first == rectangle.last && rectangle.count == 5)
        try expect(abs(abs(rectangle[2].x-start.x)-abs(rectangle[2].y-start.y)) < 0.000001)
        let circle = DrawingShape.ellipse.points(from:start,to:end,constrained:true)
        let box = Ink(points:circle).bounds
        try expect(circle.count == 129 && circle.first == circle.last && abs(box.width-box.height) < 0.000001)
        let arrow = DrawingShape.arrow.points(from:start,to:end)
        try expect(arrow[1] == end && arrow[3] == end && arrow.count == 5)
        try expect(arrow.allSatisfy {$0.x.isFinite && $0.y.isFinite})
    }
    try expect(DrawingShape.arrow.points(from:start,to:start) == [start])
}
check("Shapes retain screenshot attachment, erasing, duplication and exports after reopening") {
    try temporaryLibrary { library in
        let package = try library.create()
        var prompt = Board(); prompt.texts = [BoardText(text:"A reference",origin:Point(0,0))]
        let asset = try library.importAsset(data:BoardRenderer.png(prompt,package:package),extension:"png",to:package)
        var board = Board(); let image = BoardImage(asset:asset,frame:Rect(0,0,400,200)); board.images = [image]
        let arrow = Ink(points:DrawingShape.arrow.points(from:Point(30,30),to:Point(180,100)),imageID:image.id)
        board.ink = [arrow]; board.resizeImage(id:image.id,width:800); board.moveImage(id:image.id,by:Point(50,60))
        try library.save(board,at:package); let reopened = try library.load(package)
        try expect(reopened == board && reopened.ink[0].hits(Point(110,120),radius:2))
        var duplicate = reopened; _ = duplicate.duplicate([image.id])
        try expect(duplicate.ink.count == 2 && duplicate.ink[1].imageID == duplicate.images[1].id)
        try expect(try BoardRenderer.png(reopened,package:package).count > 100)
        try expect(try BoardRenderer.pdf(reopened,package:package).count > 100)
    }
}
check("Shelf pinning and ordering survive serialization, renaming and status movement") {
    try temporaryLibrary { library in
        for name in ["Alpha","Beta","Gamma"] { _ = try library.create(name:name) }
        let items = try library.list(); var order = ShelfOrder()
        try expect(try library.move(items[0].url,to:.unfinished,name:"Alpha") == items[0].url)
        order.togglePin(items[2]); try expect(order.sorted(items).first == items[2])
        try expect(order.move(items[1],by:-1,among:items)); try expect(order.sorted(items).map(\.title) == ["Gamma","Beta","Alpha"])
        order = try JSONDecoder().decode(ShelfOrder.self,from:JSONEncoder().encode(order))
        let movedURL = try library.move(items[2].url,to:.finished,name:"Keep Gamma")
        guard let new = try library.list().first(where: {$0.url == movedURL}) else { throw Failure(message:"Moved package identity must match shelf listing: \(movedURL.absoluteString), \(try library.list().map { $0.url.absoluteString })") }
        order.relocate(from:items[2],to:new)
        try expect(order.pinned.contains(ShelfOrder.key(new)) && !order.pinned.contains(ShelfOrder.key(items[2])))
        order.togglePin(new); try expect(!order.pinned.contains(ShelfOrder.key(new)))
        try expect(!order.move(items[0],by:Int.min,among:items))
    }
}
check("Large shelves sort and paginate without opening documents or crossing pin groups") {
    let root = URL(fileURLWithPath:"/not-read/Unfinished")
    let items = (0..<1001).map {ShelfItem(url:root.appendingPathComponent("Idea \($0).whiteboard"),status:.unfinished,modified:.distantPast)}
    var order = ShelfOrder(); order.togglePin(items[1000]); order.togglePin(items[500])
    try expect(order.move(items[1000],by:-1,among:items))
    try expect(!order.move(items[1000],by:-1,among:items))
    let sorted = order.sorted(items)
    try expect(sorted[0] == items[1000] && sorted[1] == items[500])
    let pages = stride(from:0,to:sorted.count,by:100).flatMap {Array(sorted.dropFirst($0).prefix(100))}
    try expect(pages.count == 1001 && Set(pages.map(\.url)).count == 1001)
}
check("Fictional demo assets export and remain independent of a personal library") {
    try temporaryLibrary { personal in
        let idea = try personal.create(name:"Personal thought"), before = try Data(contentsOf:idea.appendingPathComponent("board.json"))
        try temporaryLibrary { demo in
            _ = try DemoContent.populate(demo)
            let samples = try demo.list(); try expect(samples.count == 3)
            try expect(try samples.allSatisfy { try demo.load($0.url).images.allSatisfy {$0.tex == nil} })
            try expect(samples.contains {$0.status == .finished})
            for item in samples {
                var board = try demo.load(item.url)
                try expect(try BoardRenderer.png(board,package:item.url).count > 100)
                board.texts.append(BoardText(text:"I can edit this",origin:Point(50,50)))
                try demo.save(board,at:item.url); try expect(try demo.load(item.url) == board)
            }
        }
        try expect(try personal.list().count == 1)
        try expect(try Data(contentsOf:idea.appendingPathComponent("board.json")) == before)
    }
}
func sketch(_ vertices: [Point], wobble: Double = 1.2) -> [Point] {
    var points: [Point] = []
    for i in 1..<vertices.count {
        for step in 0..<24 {
            let t = Double(step)/24, a = vertices[i-1], b = vertices[i]
            points.append(Point(a.x+(b.x-a.x)*t+sin(Double(points.count)*1.7)*wobble,a.y+(b.y-a.y)*t+cos(Double(points.count)*1.3)*wobble))
        }
    }
    points.append(vertices.last!); return points
}
check("Freehand lines, arrows, circles and ellipses snap from noisy sketches") {
    let line = sketch([Point(10,10),Point(250,130)])
    try expect(ShapeRecognition.recognise(line)?.name == "Line")
    let arrow = sketch([Point(10,100),Point(310,100),Point(260,70),Point(310,100),Point(260,130)])
    try expect(ShapeRecognition.recognise(arrow)?.name == "Arrow")
    try expect(ShapeRecognition.recognise(Array(arrow.reversed()))?.name == "Arrow")
    for (rx,ry,name) in [(100.0,100.0,"Circle"),(160,80,"Ellipse")] {
        let loop = (0...180).map {i -> Point in
            let a = Double(i)*2 * .pi/180, wobble = 1+0.02*sin(a*7)
            return Point(250+rx*cos(a)*wobble,250+ry*sin(a)*wobble)
        }
        guard let result = ShapeRecognition.recognise(loop) else { throw Failure(message:"Expected \(name)") }
        try expect(result.name == name && result.points.first == result.points.last)
    }
}
check("Freehand rectangles work rotated, reversed and from an edge midpoint") {
    let box = sketch([Point(100,0),Point(240,0),Point(240,140),Point(0,140),Point(0,0),Point(100,0)])
    for degrees in [0.0,21,45,78] {
        let a = degrees * .pi/180
        let rotated = box.map {Point(300+$0.x*cos(a)-$0.y*sin(a),300+$0.x*sin(a)+$0.y*cos(a))}
        for points in [rotated,Array(rotated.reversed())] {
            guard let result = ShapeRecognition.recognise(points) else { throw Failure(message:"Expected rectangle at \(degrees) degrees") }
            try expect(result.name == "Rectangle" && result.points.count == 5)
            try expect(result.points.first == result.points.last)
        }
    }
}
check("Automatic shapes leave ambiguous marks, small writing and oversized strokes alone") {
    let marks = [
        sketch([Point(0,150),Point(75,0),Point(150,150),Point(0,150)]), // triangle
        sketch([Point(0,150),Point(0,0),Point(75,100),Point(150,0),Point(150,150)]), // M
        sketch([Point(0,0),Point(50,120),Point(100,0),Point(150,120),Point(200,0)]),
        (0...120).map {i -> Point in let a = Double(i)*4 * .pi/120; return Point(200+100*cos(a),200+100*sin(a))}, // two loops
        (0...120).map {i -> Point in let a = Double(i)*4.6/120; return Point(200+100*cos(a),200+100*sin(a))}, // open curve
        sketch([Point(0,0),Point(12,12)],wobble:0.1)
    ]
    for (i,mark) in marks.enumerated() { try expect(ShapeRecognition.recognise(mark) == nil,"Ambiguous mark \(i) should remain ink") }
    try expect(ShapeRecognition.recognise([Point(.nan,0),Point(100,10),Point(200,20)]) == nil)
    try expect(ShapeRecognition.recognise(Array(repeating:Point(100,100),count:20_001)) == nil)
    let circle = (0...120).map {i -> Point in let a = Double(i)*2 * .pi/120; return Point(100+60*cos(a),100+60*sin(a))}
    try expect(ShapeRecognition.recognise(circle,zoom:0.15) == nil)
}
check("Crops preserve source geometry, annotations and undoable restoration after reopen") {
    try temporaryLibrary { library in
        var board = Board(); let image = BoardImage(asset:"sample.png",frame:Rect(10,20,400,200)); board.images = [image]
        board.ink = [Ink(points:[Point(150,100),Point(300,100)],imageID:image.id)]
        try expect(board.cropImage(id:image.id,to:Rect(110,70,200,100)))
        try expect(board.version == 2 && board.images[0].visibleFrame == Rect(110,70,200,100))
        try expect(board.images[0].frame == image.frame && board.ink[0].points[0] == Point(150,100))
        board.resizeImage(id:image.id,width:400)
        try expect(board.images[0].visibleFrame == Rect(110,70,400,200))
        try expect(board.ink[0].points[0] == Point(190,130))
        board.moveImage(id:image.id,by:Point(30,40))
        let url = try library.create(board:board); let reopened = try library.load(url)
        try expect(reopened == board && reopened.images[0].visibleFrame == Rect(140,110,400,200))
        var restored = reopened; try expect(restored.cropImage(id:image.id,to:nil))
        try expect(restored.images[0].visibleFrame == Rect(-60,10,800,400))
        try expect(restored.ink == reopened.ink)
        var copy = board; _ = copy.duplicate([image.id]); try expect(copy.images[1].crop == board.images[0].crop)
        try expect(copy.ink[1].imageID == copy.images[1].id)
    }
}
check("Invalid, locked and vector crops are rejected; old boards remain readable") {
    var board = Board(); let image = BoardImage(asset:"a.png",frame:Rect(0,0,400,200)); board.images = [image]
    let old = try JSONEncoder().encode(board); try expect(try JSONDecoder().decode(Board.self,from:old).validated() == board)
    for region in [Rect(0,0,0,10),Rect(0,0,-10,20),Rect(500,500,20,20),Rect(.nan,0,30,20)] { try expect(!board.cropImage(id:image.id,to:region)) }
    board.images[0].locked = true; try expect(!board.cropImage(id:image.id,to:Rect(0,0,100,100)))
    board.images[0].locked = false; board.images[0].vectorAsset = "math.pdf"
    try expect(!board.cropImage(id:image.id,to:Rect(0,0,100,100)))
    board.images[0].vectorAsset = nil; board.images[0].crop = Rect(0,0,0.5,0.5)
    try rejects {_ = try board.validated()}; board.version = 2
    for crop in [Rect(-0.1,0,1,1),Rect(0,0,0,1),Rect(0.8,0,0.3,1),Rect(0,0,.infinity,1)] {
        board.images[0].crop = crop; try rejects {_ = try board.validated()}
    }
}
final class PDFImageSizes { var values: [(Int,Int)] = [] }
check("Cropped PNG/PDF exports contain only kept image pixels; editable copies retain the original") {
    try temporaryLibrary { library in
        let package = try library.create()
        let context = CGContext(data:nil,width:100,height:80,bitsPerComponent:8,bytesPerRow:400,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(red:0,green:0,blue:1,alpha:1)); context.fill(CGRect(x:0,y:0,width:100,height:80))
        context.setFillColor(CGColor(red:0,green:1,blue:0,alpha:1)); context.fill(CGRect(x:0,y:0,width:50,height:40))
        context.setFillColor(CGColor(red:1,green:0,blue:0,alpha:1)); context.fill(CGRect(x:0,y:40,width:50,height:40))
        let original = NSMutableData(), destination = CGImageDestinationCreateWithData(original,"public.png" as CFString,1,nil)!
        CGImageDestinationAddImage(destination,context.makeImage()!,nil); try expect(CGImageDestinationFinalize(destination))
        let asset = try library.importAsset(data:original as Data,extension:"png",to:package)
        var board = Board(); let image = BoardImage(asset:asset,frame:Rect(100,80,200,160)); board.images = [image]
        try expect(board.cropImage(id:image.id,to:Rect(100,80,100,80)))
        let visible = board.images[0].visibleFrame
        let png = try BoardRenderer.png(board,package:package,region:visible)
        let decoded = CGImageSourceCreateImageAtIndex(CGImageSourceCreateWithData(png as CFData,nil)!,0,nil)!
        let bitmap = CGContext(data:nil,width:20,height:20,bitsPerComponent:8,bytesPerRow:80,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGBitmapInfo.byteOrder32Big.rawValue|CGImageAlphaInfo.premultipliedLast.rawValue)!
        bitmap.draw(decoded,in:CGRect(x:0,y:0,width:20,height:20)); let bytes = bitmap.data!.assumingMemoryBound(to:UInt8.self)
        let centre = 10*80+10*4
        try expect(bytes[centre] > 200 && bytes[centre+1] < 80 && bytes[centre+2] < 80,"Top-left crop must remain red; RGBA=\(Array(UnsafeBufferPointer(start:bytes+centre,count:4)))")
        let pdf = try BoardRenderer.pdf(board,package:package,region:visible), document = CGPDFDocument(CGDataProvider(data:pdf as CFData)!)!, page = document.page(at:1)!
        var resources: CGPDFDictionaryRef?, objects: CGPDFDictionaryRef?
        try expect(CGPDFDictionaryGetDictionary(page.dictionary!,"Resources",&resources))
        try expect(CGPDFDictionaryGetDictionary(resources!,"XObject",&objects))
        let sizes = PDFImageSizes()
        CGPDFDictionaryApplyFunction(objects!, { _, object, info in
            var stream: CGPDFStreamRef?
            guard let info, CGPDFObjectGetValue(object,.stream,&stream), let stream else { return }
            guard let dictionary = CGPDFStreamGetDictionary(stream) else { return }; var width: CGPDFInteger = 0, height: CGPDFInteger = 0
            if CGPDFDictionaryGetInteger(dictionary,"Width",&width), CGPDFDictionaryGetInteger(dictionary,"Height",&height) { Unmanaged<PDFImageSizes>.fromOpaque(info).takeUnretainedValue().values.append((width,height)) }
        }, Unmanaged.passUnretained(sizes).toOpaque())
        try expect(sizes.values.count == 1 && sizes.values[0].0 == 50 && sizes.values[0].1 == 40,"PDF must embed the cropped pixels rather than a clipped full image")
        let copy = try library.copy(board,from:package,name:"Cropped copy")
        try expect(try Data(contentsOf:copy.appendingPathComponent("assets").appendingPathComponent(asset)) == original as Data)
        var reopened = try library.load(copy); _ = reopened.cropImage(id:image.id,to:nil)
        try expect(reopened.images[0].frame == image.frame)
        if let output = ProcessInfo.processInfo.environment["WHITEBOARD_TEST_ARTIFACTS"] {
            let folder = URL(fileURLWithPath:output); try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
            try png.write(to:folder.appendingPathComponent("crop-check.png")); try pdf.write(to:folder.appendingPathComponent("crop-check.pdf"))
        }
    }
}
check("A simulated full disk during either save write preserves the current board and permits retry") {
    try temporaryLibrary { initial in
        let package = try initial.create(); let before = try Data(contentsOf:package.appendingPathComponent("board.json"))
        var failureTarget: String?
        let library = try Library(root:initial.root,atomicWrite:{data,url in
            if url.lastPathComponent == failureTarget { throw NSError(domain:NSCocoaErrorDomain,code:NSFileWriteOutOfSpaceError) }
            try data.write(to:url,options:.atomic)
        })
        var board = try library.load(package); board.texts = [BoardText(text:"Keep this even when a save fails",origin:Point(10,10))]
        for target in ["previous.json","board.json"] {
            failureTarget = target; try rejects {try library.save(board,at:package)}
            try expect(try Data(contentsOf:package.appendingPathComponent("board.json")) == before)
        }
        failureTarget = nil; try library.save(board,at:package); try expect(try library.load(package) == board)
        try expect(try Data(contentsOf:package.appendingPathComponent("previous.json")) == before)
    }
}
check("Failed creation and failed image writes leave existing ideas intact") {
    try temporaryLibrary { initial in
        let original = try initial.create(); let before = try Data(contentsOf:original.appendingPathComponent("board.json"))
        let library = try Library(root:initial.root,atomicWrite:{_,_ in throw NSError(domain:NSCocoaErrorDomain,code:NSFileWriteOutOfSpaceError)})
        try rejects {_ = try library.create(name:"Cannot save")}
        try expect(try library.list().count == 1)
        try rejects {_ = try library.importAsset(data:Data([1,2,3]),extension:"png",to:original)}
        try expect(try FileManager.default.contentsOfDirectory(atPath:original.appendingPathComponent("assets").path).isEmpty)
        try expect(try Data(contentsOf:original.appendingPathComponent("board.json")) == before)
    }
}
check("Automatic history is spaced across saves and restarts and moves with the idea") {
    try temporaryLibrary { initial in
        var clock = Date(timeIntervalSince1970:1_700_000_000)
        let library = try Library(root:initial.root,now:{clock}); var board = Board()
        let url = try library.create(board:board)
        try expect(try library.history(url).isEmpty)
        board.texts = [BoardText(text:"First edit",origin:Point(0,0))]; try library.save(board,at:url)
        try expect(try library.history(url).count == 1)
        for index in 1...25 { clock = clock.addingTimeInterval(1); board.texts[0].text = "Edit \(index)"; try library.save(board,at:url) }
        try expect(try library.history(url).count == 1)
        let reopened = try Library(root:initial.root,now:{clock}); _ = try reopened.load(url)
        try reopened.save(board,at:url); try expect(try reopened.history(url).count == 1)
        clock = clock.addingTimeInterval(300); board.texts[0].text = "Edit after five minutes"; try reopened.save(board,at:url)
        let snapshots = try reopened.history(url); try expect(snapshots.count == 2)
        let moved = try reopened.move(url,to:.finished,name:"Kept thought")
        try expect(try reopened.history(moved) == snapshots)
        try reopened.save(board,at:moved); try expect(try reopened.history(moved).count == 2)
    }
}
check("Manual checkpoints retain twenty recent versions and restore as independent copies") {
    try temporaryLibrary { initial in
        var clock = Date(timeIntervalSince1970:1_700_000_000)
        let library = try Library(root:initial.root,now:{clock}); var board = Board()
        let source = try library.create(); let asset = try library.importAsset(data:Data([1,2,3]),extension:"png",to:source)
        var image = BoardImage(asset:asset,frame:Rect(0,0,100,100)); image.crop = Rect(0,0,0.5,0.5)
        board.version = 2; board.images = [image]; board.ink = [Ink(points:[Point(10,20)],imageID:image.id)]
        board.texts = [BoardText(text:"",origin:Point(0,0))]
        for index in 0..<25 {
            clock = clock.addingTimeInterval(1); board.texts[0].text = "Version \(index)"
            try library.save(board,at:source); try library.checkpoint(source)
        }
        let snapshots = try library.history(source); try expect(snapshots.count == 20)
        let corrupt = Data("corrupt current metadata".utf8); try corrupt.write(to:source.appendingPathComponent("board.json"))
        let recovered = try library.recoverSnapshot(snapshots.last!.filename,from:source)
        let old = try library.load(recovered)
        try expect(old.texts[0].text == "Version 5" && old.id != board.id)
        try expect(old.images == board.images && old.ink == board.ink)
        try expect(try Data(contentsOf:source.appendingPathComponent("board.json")) == corrupt)
        try FileManager.default.removeItem(at:source)
        try expect(try Data(contentsOf:recovered.appendingPathComponent("assets").appendingPathComponent(asset)) == Data([1,2,3]))
    }
}
check("History byte budget prunes oldest metadata while leaving unrelated files alone") {
    try temporaryLibrary { library in
        let source = try library.create(); let folder = source.appendingPathComponent("history")
        try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:false)
        for index in 0..<20 {
            let url = folder.appendingPathComponent("\(1_600_000_000+index)_\(UUID().uuidString).json")
            FileManager.default.createFile(atPath:url.path,contents:Data())
            let handle = try FileHandle(forWritingTo:url); try handle.truncate(atOffset:4*1024*1024); try handle.close()
        }
        let unrelated = folder.appendingPathComponent("keep.txt"); try Data([9]).write(to:unrelated)
        try library.checkpoint(source)
        let history = try library.history(source)
        try expect(history.count == 16 && history.reduce(0,{$0+$1.bytes}) <= Library.historyByteLimit)
        try expect(try Data(contentsOf:unrelated) == Data([9]))
        let copy = try library.recoverSnapshot(history[0].filename,from:source); _ = try library.load(copy)
    }
}
check("History write failure preserves saved data and snapshots, then allows retry") {
    try temporaryLibrary { initial in
        let source = try initial.create(); try initial.checkpoint(source)
        let previousHistory = try initial.history(source), before = try Data(contentsOf:source.appendingPathComponent("board.json"))
        var fail = true
        let library = try Library(root:initial.root,now:{Date().addingTimeInterval(600)},atomicWrite:{data,url in
            if fail && url.deletingLastPathComponent().lastPathComponent == "history" { throw NSError(domain:NSCocoaErrorDomain,code:NSFileWriteOutOfSpaceError) }
            try data.write(to:url,options:.atomic)
        })
        var board = try library.load(source); board.texts = [BoardText(text:"Unsaved thought",origin:Point(0,0))]
        try rejects {try library.save(board,at:source)}
        try expect(try Data(contentsOf:source.appendingPathComponent("board.json")) == before)
        try expect(try library.history(source) == previousHistory)
        fail = false; try library.save(board,at:source); try expect(try library.load(source) == board)
    }
}
check("Recovery rejects traversal, corrupt snapshots and symlinked history without overwriting") {
    try temporaryLibrary { library in
        let source = try library.create(); try library.checkpoint(source)
        let snapshot = try library.history(source)[0]
        try rejects {_ = try library.recoverSnapshot("../board.json",from:source)}
        try Data("invalid".utf8).write(to:source.appendingPathComponent("history").appendingPathComponent(snapshot.filename))
        try rejects {_ = try library.recoverSnapshot(snapshot.filename,from:source)}
        try expect(try library.list().count == 1)
        let other = try library.create(name:"Other")
        try FileManager.default.createSymbolicLink(at:other.appendingPathComponent("history"),withDestinationURL:source.appendingPathComponent("history"))
        try rejects {try library.checkpoint(other)}
        try rejects {_ = try library.history(other)}
        try expect(try library.load(source).isEmpty)
    }
}
check("PDE demos retain twelve editable vector assets and upgrade without overwriting existing ideas") {
    try temporaryLibrary { library in
        let personal = try library.create(name:"Existing idea"), before = try Data(contentsOf:personal.appendingPathComponent("board.json"))
        let added = try PDEExamples.installMissing(library); try expect(added.count == 3)
        for url in added {
            let board = try library.load(url); try expect(board.images.count == 4)
            for item in board.images {
                try expect(item.tex != nil && item.vectorAsset != nil)
                let file = url.appendingPathComponent("assets").appendingPathComponent(item.vectorAsset!)
                let pdf = CGPDFDocument(file as CFURL); try expect(pdf?.numberOfPages == 1)
                try expect(CGImageSourceCreateWithURL(url.appendingPathComponent("assets").appendingPathComponent(item.asset) as CFURL,nil) != nil)
            }
        }
        let renamed = try library.move(added[0],to:.finished,name:"My PDE notes")
        var edited = try library.load(renamed); edited.texts.append(BoardText(text:"Personal annotation",origin:Point(10,10))); try library.save(edited,at:renamed)
        try expect(try PDEExamples.installMissing(library).isEmpty)
        try expect(try library.load(renamed) == edited)
        try expect(try Data(contentsOf:personal.appendingPathComponent("board.json")) == before)
        // A user may remove every demo after the one-time migration marker is written.
        for item in try library.list() { try FileManager.default.removeItem(at:item.url) }
        let restarted = try DemoContent.populate(library)
        try expect(try library.list().count == 3)
        try expect(!(try library.load(restarted)).isEmpty)
    }
}
func trayPNG() throws -> Data {
    let bitmap = CGContext(data:nil,width:40,height:30,bitsPerComponent:8,bytesPerRow:160,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
    bitmap.setFillColor(CGColor(red:0.2,green:0.5,blue:0.9,alpha:1)); bitmap.fill(CGRect(x:0,y:0,width:40,height:30))
    let bytes = NSMutableData(), output = CGImageDestinationCreateWithData(bytes,"public.png" as CFString,1,nil)!
    CGImageDestinationAddImage(output,bitmap.makeImage()!,nil); try expect(CGImageDestinationFinalize(output)); return bytes as Data
}
check("Capture tray survives reopening and placed copies survive removing the reference") {
    try temporaryLibrary { library in
        let tray = CaptureTray(libraryRoot:library.root), png = try trayPNG()
        let first = try tray.add(png,extension:"png",title:"Question / one")
        let second = try tray.add(png,extension:"PNG",title:"Question / one")
        let reopened = CaptureTray(libraryRoot:library.root)
        try expect(try reopened.references().count == 2 && first.id != second.id)
        let (item,data) = try reopened.data(for:first.id)
        try expect(data == png && item.width == 40 && item.height == 30 && !item.title.contains("/"))
        let boardURL = try library.create(); var board = Board()
        let asset = try library.importAsset(data:data,extension:item.fileExtension,to:boardURL)
        board.images = [BoardImage(asset:asset,frame:Rect(20,30,item.width,item.height))]; try library.save(board,at:boardURL)
        try reopened.remove(first.id)
        try expect(try reopened.references().map(\.id) == [second.id])
        try expect(try Data(contentsOf:boardURL.appendingPathComponent("assets").appendingPathComponent(asset)) == png)
        try expect(try library.load(boardURL) == board)
    }
}
check("Capture tray enforces item, file and total byte limits without evicting references") {
    try temporaryLibrary { library in
        let tray = CaptureTray(libraryRoot:library.root), png = try trayPNG()
        for i in 0..<8 { try tray.add(png,extension:"png",title:"Reference \(i)") }
        let before = try tray.references()
        try rejects {_ = try tray.add(png,extension:"png",title:"Overflow")}
        try expect(try tray.references() == before)
        for item in before { try tray.remove(item.id) }
        try expect(try tray.emptyRemoved() == 8)
        var large = png; large.append(Data(repeating:0,count:CaptureTray.imageByteLimit-png.count))
        try tray.add(large,extension:"png",title:"Large one"); try tray.add(large,extension:"png",title:"Large two")
        try rejects {_ = try tray.add(png,extension:"png",title:"Byte overflow")}
        large.append(0); try rejects {_ = try tray.add(large,extension:"png",title:"File overflow")}
        try expect(try tray.references().count == 2)
    }
}
check("Failed capture writes clean up incomplete entries and preserve existing references") {
    try temporaryLibrary { library in
        let initial = CaptureTray(libraryRoot:library.root), png = try trayPNG()
        let original = try initial.add(png,extension:"png",title:"Keep this")
        for target in ["image.png","reference.json"] {
            let failing = CaptureTray(libraryRoot:library.root,atomicWrite:{data,url in
                if url.lastPathComponent == target { throw NSError(domain:NSCocoaErrorDomain,code:NSFileWriteOutOfSpaceError) }
                try data.write(to:url,options:.atomic)
            })
            try rejects {_ = try failing.add(png,extension:"png",title:"Failed")}
            try expect(try failing.references() == [original])
            try expect(try FileManager.default.contentsOfDirectory(atPath:initial.root.path).count == 1)
        }
        try expect(try initial.data(for:original.id).1 == png)
    }
}
check("Capture trays stay separate across libraries and reject non-image content") {
    try temporaryLibrary { library in
        let other = try Library(root:library.root.appendingPathComponent("Separate library"))
        let personal = CaptureTray(libraryRoot:library.root), demo = CaptureTray(libraryRoot:other.root)
        try personal.add(trayPNG(),extension:"png",title:"Personal reference")
        try expect(try demo.references().isEmpty)
        try rejects {_ = try demo.add(Data("not an image".utf8),extension:"png",title:"Invalid")}
        try rejects {_ = try demo.add(trayPNG(),extension:"../png",title:"Unsafe")}
        try expect(try personal.references().count == 1 && demo.references().isEmpty)
    }
}
check("Capture tray rejects symlinked roots and substituted assets") {
    try temporaryLibrary { library in
        let tray = CaptureTray(libraryRoot:library.root), png = try trayPNG()
        let item = try tray.add(png,extension:"png",title:"Reference")
        let asset = tray.root.appendingPathComponent(item.id.uuidString).appendingPathComponent("image.png")
        let outside = library.root.appendingPathComponent("original.png"); try png.write(to:outside)
        try FileManager.default.removeItem(at:asset); try FileManager.default.createSymbolicLink(at:asset,withDestinationURL:outside)
        try rejects {_ = try tray.data(for:item.id)}
        let other = try Library(root:library.root.appendingPathComponent("Other")), linked = CaptureTray(libraryRoot:other.root)
        try FileManager.default.createSymbolicLink(at:linked.root,withDestinationURL:tray.root)
        try rejects {_ = try linked.references()}
        try expect(try Data(contentsOf:outside) == png)
    }
}
if ProcessInfo.processInfo.environment["WHITEBOARD_TEX_CHECKS"] == "1" {
    check("Real LaTeX rendering preserves editable source and vector assets through copy/reopen") {
        try temporaryLibrary { library in
            let source = try PDEExamples.source("heat-model",kind:.latex)
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
        let source = try PDEExamples.source("poisson-diagram",kind:.tikz)
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
runAuditStorageChecks()
check("Restoring a tray removal cannot exceed active capacity") {
    try temporaryLibrary { library in
        let tray = CaptureTray(libraryRoot:library.root), png = try trayPNG()
        let removed = try tray.remove(tray.add(png,extension:"png",title:"Removed").id)
        for index in 0..<8 { try tray.add(png,extension:"png",title:"Active \(index)") }
        try rejects { try tray.restore(removed) }
        try expect(try tray.references().count == 8)
    }
}
check("General demos preserve edits, resume partial installation and restore copies explicitly") {
    try temporaryLibrary { library in
        _ = try DemoContent.populate(library)
        let first = try library.list()[0], renamed = try library.move(first.url,to:.unfinished,name:"My renamed example")
        var board = try library.load(renamed); board.texts.append(BoardText(text:"My addition",origin:Point(20,20))); try library.save(board,at:renamed)
        _ = try DemoContent.populate(library); try expect(try library.list().count == 3); try expect(try library.load(renamed) == board)
        let damaged = try library.create(name:"Unreadable unrelated idea")
        let damagedBytes = Data("unreadable".utf8)
        try damagedBytes.write(to:damaged.appendingPathComponent("board.json"))
        _ = try DemoContent.populate(library,restore:true); try expect(try library.list().count == 7)
        try expect(try library.load(renamed) == board)
        try expect(try Data(contentsOf:damaged.appendingPathComponent("board.json")) == damagedBytes)
    }
}
check("Identical saves do not write current, previous or history metadata") {
    try temporaryLibrary { initial in
        var writes = 0
        let library = try Library(root:initial.root,atomicWrite:{data,url in writes += 1; try data.write(to:url,options:.atomic)})
        let board = Board(), package = try library.create(board:board), before = writes
        try library.save(board,at:package); try library.save(board,at:package)
        try expect(writes == before && (try library.history(package)).isEmpty)
    }
}
print("\n\(passed) passed, \(failed) failed")
exit(failed == 0 ? 0 : 1)
