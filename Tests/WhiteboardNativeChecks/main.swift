import AppKit
import ImageIO
import WhiteboardCore

let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
var passed = 0, failed = 0
struct TestFailure: Error { let message: String }
func expect(_ value: @autoclosure () throws -> Bool, _ message: String = "Expectation failed") throws {
    if try !value() { throw TestFailure(message:message) }
}
func check(_ name: String, _ body: () throws -> Void) {
    do { try body(); passed += 1; print("PASS "+name) }
    catch { failed += 1; print("FAIL \(name): \(error)") }
}
let folder = FileManager.default.temporaryDirectory.appendingPathComponent("Whiteboard-native-checks-"+UUID().uuidString,isDirectory:true)
try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
defer { try? FileManager.default.removeItem(at:folder) }
func makeCanvas(_ board: Board) -> (NSWindow,CanvasView) {
    let window = OverlayWindow(contentRect:NSRect(x:0,y:0,width:900,height:700),styleMask:[.borderless],backing:.buffered,defer:false)
    window.isReleasedWhenClosed = false
    let view = CanvasView(frame:NSRect(x:0,y:0,width:900,height:700)); window.contentView = view; view.load(board,at:folder)
    return (window,view)
}
func mouse(_ type: NSEvent.EventType, _ point: NSPoint, in window: NSWindow) -> NSEvent {
    NSEvent.mouseEvent(with:type,location:point,modifierFlags:[],timestamp:0,windowNumber:window.windowNumber,context:nil,eventNumber:1,clickCount:1,pressure:1)!
}
check("Hand drag keeps the same document anchor through successive events") {
    let (window,view) = makeCanvas(Board()); defer { window.close() }
    view.tool = .hand; view.board.viewport.zoom = 2
    let start = NSPoint(x:300,y:300), local = view.convert(start,from:nil)
    let anchor = view.board.viewport.world(Point(local.x,local.y))
    view.mouseDown(with:mouse(.leftMouseDown,start,in:window))
    for point in [NSPoint(x:290,y:305),NSPoint(x:270,y:320),NSPoint(x:340,y:280)] {
        view.mouseDragged(with:mouse(.leftMouseDragged,point,in:window))
        let p = view.convert(point,from:nil), actual = view.board.viewport.world(Point(p.x,p.y))
        try expect(abs(anchor.x-actual.x)<0.0001 && abs(anchor.y-actual.y)<0.0001)
    }
    view.finishGesture()
}
check("Locked images and attached ink survive selection movement and deletion") {
    var board = Board(), image = BoardImage(asset:"a.png",frame:Rect(10,20,100,100)); image.locked = true
    let attached = Ink(points:[Point(25,30),Point(40,45)],imageID:image.id)
    board.images = [image]; board.ink = [attached]
    let (window,view) = makeCanvas(board); defer { window.close() }
    view.selected = [image.id,attached.id]; view.nudgeSelected(x:30,y:20); view.deleteSelection(); view.clearInk()
    try expect(view.board.images == [image] && view.board.ink == [attached])
}
check("Keyboard selection and accessibility actions identify actual objects") {
    var board = Board(); var image = BoardImage(asset:"a.png",frame:Rect(0,0,100,100)); image.accessibilityDescription = "A comparison of two ideas"
    board.images = [image]; board.texts = [BoardText(text:"First line\nSecond line",origin:Point(200,200))]
    let (window,view) = makeCanvas(board); defer { window.close() }
    view.selectNextObject(backwards:false); try expect(view.selected == [image.id])
    view.selectNextObject(backwards:false); try expect(view.selected == [board.texts[0].id])
    view.nudgeSelected(x:10,y:5); try expect(view.board.texts[0].origin == Point(210,205))
    let children = view.accessibilityChildren() as? [NSAccessibilityElement] ?? []
    try expect(children.count == 2 && children[0].accessibilityLabel() == image.accessibilityDescription)
    try expect(children[1].accessibilityLabel() == "First line\nSecond line")
    try expect(children[0].accessibilityPerformPress()); try expect(view.selected == [image.id])
    let repeated = view.accessibilityChildren() as? [NSAccessibilityElement] ?? []
    try expect(repeated.first === children.first)
    view.selected = [board.texts[0].id]; try expect(view.editSelectedObject())
    let editor = view.accessibilityChildren()?.compactMap {$0 as? NSTextView}.first
    try expect(editor != nil, "Active text editor must remain in the accessibility tree")
    editor?.string = "Updated first line\nUpdated second line"; view.finishEditing()
    try expect(view.board.texts[0].text == "Updated first line\nUpdated second line")
}
check("Multiline text exports escaped content and preserves wide glyph bounds") {
    var board = Board(); board.texts = [BoardText(text:"WWWWWW\n<idea> & a second line\n数学",origin:Point(10,20))]
    let text = board.texts[0]
    try expect(BoardRenderer.textBounds(text).height > 3*text.size)
    let html = try BoardRenderer.html(board,package:folder)
    try expect(html.contains("&lt;idea&gt; &amp;") && !html.contains("<idea>"))
    try expect(try BoardRenderer.png(board,package:folder).count > 100)
}
check("Cached image preview upgrades after its pixel budget grows") {
    let bitmap = CGContext(data:nil,width:1800,height:1800,bitsPerComponent:8,bytesPerRow:7200,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
    let bytes = NSMutableData(), destination = CGImageDestinationCreateWithData(bytes,"public.png" as CFString,1,nil)!
    CGImageDestinationAddImage(destination,bitmap.makeImage()!,nil); try expect(CGImageDestinationFinalize(destination))
    let url = folder.appendingPathComponent("preview.png"); try (bytes as Data).write(to:url)
    let pool = ImagePool(); pool.prepare(visible:[url]+(1...19).map {folder.appendingPathComponent("unused-\($0).png")})
    func decoded() throws -> NSImage {
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline {
            if let image = pool.image(at:url,ready:{}) { return image }
            RunLoop.main.run(until:Date().addingTimeInterval(0.01))
        }
        throw TestFailure(message:"Image decode timed out")
    }
    let small = try decoded().size.width; pool.prepare(visible:[url]); let large = try decoded().size.width
    try expect(large > small && large <= 1536)
}
check("Termination waits for export work even when the board is saved") {
    let controller = AppController(); controller.exporting = true
    try expect(controller.applicationShouldTerminate(app) == .terminateLater)
    controller.afterSave = nil; controller.terminationPending = false
}
check("TeX defaults are general-purpose and independent of PDE resources") {
    for kind in [TeXKind.latex,.tikz] {
        let sample = TeXEditor.sample(kind)
        try expect(!sample.isEmpty && !sample.contains("partial") && !sample.contains("PDE"))
    }
}
check("A temporary failed save retries and commits without an external-conflict lock") {
    var failNextWrite = false
    let library = try Library(root:folder.appendingPathComponent("retry"),atomicWrite:{data,url in
        if failNextWrite, url.lastPathComponent == "board.json" {
            failNextWrite = false; throw NSError(domain:NSCocoaErrorDomain,code:NSFileWriteOutOfSpaceError)
        }
        try data.write(to:url,options:.atomic)
    })
    let package = try library.create(); var board = try library.load(package)
    board.texts = [BoardText(text:"Keep this thought",origin:Point(0,0))]
    let controller = AppController(); controller.library = library; controller.activeURL = package
    controller.canvas.load(board,at:package); controller.revision = 1; failNextWrite = true; controller.saveNow()
    let deadline = Date().addingTimeInterval(5)
    while controller.savedRevision != 1, Date() < deadline { RunLoop.main.run(until:Date().addingTimeInterval(0.02)) }
    try expect(controller.savedRevision == 1 && !controller.saveBlocked && controller.saveFailure == nil)
    try expect(try library.load(package).texts == board.texts)
}
check("Marquee selection excludes nearby objects sharing a spatial-index cell") {
    var board = Board(); board.images = [BoardImage(asset:"a.png",frame:Rect(10,10,30,30)),BoardImage(asset:"b.png",frame:Rect(200,200,30,30))]
    let (window,view) = makeCanvas(board); defer { window.close() }; view.tool = .select
    view.mouseDown(with:mouse(.leftMouseDown,NSPoint(x:0,y:700),in:window))
    view.mouseDragged(with:mouse(.leftMouseDragged,NSPoint(x:50,y:650),in:window))
    view.finishGesture(); try expect(view.selected == [board.images[0].id])
}
check("Keyboard crop can resize and reposition the retained region, then undo") {
    var board = Board(); let image = BoardImage(asset:"a.png",frame:Rect(0,0,100,100)); board.images = [image]
    let (window,view) = makeCanvas(board); defer { window.close() }; view.selected = [image.id]; view.beginCrop()
    func key(_ code: UInt16, _ modifiers: NSEvent.ModifierFlags) -> NSEvent {
        NSEvent.keyEvent(with:.keyDown,location:.zero,modifierFlags:modifiers,timestamp:0,windowNumber:window.windowNumber,context:nil,characters:"",charactersIgnoringModifiers:"",isARepeat:false,keyCode:code)!
    }
    view.keyDown(with:key(123,[.shift])); view.keyDown(with:key(124,[.option])); view.applyCrop()
    try expect(abs((view.board.images[0].crop?.x ?? -1)-0.01) < 0.0001)
    try expect(abs((view.board.images[0].crop?.width ?? -1)-0.9) < 0.0001)
    view.undoEdit(); try expect(view.board.images[0].crop == nil)
}
print("\n\(passed) native checks passed, \(failed) failed")
exit(failed == 0 ? 0 : 1)
