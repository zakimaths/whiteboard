import AppKit
import WhiteboardCore

enum DrawingTool: String, CaseIterable { case pen, highlighter, eraser, select, text, hand, shape }

final class CanvasView: NSView, NSTextFieldDelegate {
    var board = Board()
    var acceptsInput = true
    var packageURL: URL?
    var tool: DrawingTool = .pen {
        willSet { finishGesture(); cancelCrop() }
        didSet { onToolChange?(); window?.makeFirstResponder(self); discardCursorRects(); resetCursorRects() }
    }
    var colour = "ink"
    var penWidth: Double = 3
    var shape: DrawingShape = .arrow
    var automaticShapes = true
    var onRecognition: ((String) -> Void)?
    var onCropChange: ((Bool) -> Void)?
    private(set) var croppingID: UUID?
    private var cropRegion: Rect?
    private var cropStart: Point?
    var onEditTeX: ((UUID) -> Void)?
    var onToolChange: (() -> Void)?
    var onCopy: (() -> Void)?
    var onEdit: (() -> Void)?
    var onViewChange: (() -> Void)?
    var onImport: ((Data, String, Point) -> Void)?
    var onHide: (() -> Void)?
    var onStatus: ((String) -> Void)?
    var onNew: (() -> Void)?
    var onRename: (() -> Void)?
    var onExport: (() -> Void)?
    var selected = Set<UUID>()
    let images = ImagePool()
    private let paths = NSCache<NSUUID, NSBezierPath>()
    private var boundsByID: [UUID: Rect] = [:]
    private var undoStates: [Board] = [], redoStates: [Board] = []
    private var active: Ink?
    private var activePath: NSBezierPath?
    private var activeShape: DrawingShape?
    private var shapeEnd: Point?
    private var keepFreehand = false
    private var lastPoint: Point?
    private var gestureStart: Point?
    private var selectRect: Rect?
    private var erasing = false
    private var moving = false
    private var resizingID: UUID?
    private var panning = false
    private var changedInGesture = false
    private var editor: NSTextField?
    private var editingID: UUID?
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override var isOpaque: Bool { board.background == "paper" }

    override init(frame: NSRect) {
        super.init(frame: frame)
        paths.countLimit = 512
        registerForDraggedTypes([.fileURL, .png, .tiff])
        setAccessibilityLabel("Whiteboard canvas. Draw, paste a screenshot, or scroll for more space.")
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func resetCursorRects() {
        addCursorRect(bounds, cursor: tool == .hand ? .openHand : tool == .text ? .iBeam : .crosshair)
    }
    func load(_ board: Board, at url: URL) {
        finishEditing(); cancelCrop(); self.board = board; packageURL = url
        selected.removeAll(); undoStates.removeAll(); redoStates.removeAll(); images.clear(); paths.removeAllObjects()
        reindex(); needsDisplay = true
    }
    func checkpoint() {
        undoStates.append(board)
        if undoStates.count > 40 { undoStates.removeFirst() }
        redoStates.removeAll()
    }
    func undoEdit() { guard acceptsInput else { return };
        if croppingID != nil { cancelCrop(); return }
        finishEditing(); finishGesture(); guard let previous = undoStates.popLast() else { return }
        redoStates.append(board); board = previous; selected.removeAll(); reindex(); onEdit?(); needsDisplay = true
    }
    func redoEdit() { guard acceptsInput else { return };
        guard let next = redoStates.popLast() else { return }
        undoStates.append(board); board = next; reindex(); onEdit?(); needsDisplay = true
    }
    func reindex() { boundsByID = Dictionary(uniqueKeysWithValues: board.ink.map { ($0.id, $0.bounds) }); paths.removeAllObjects() }
    private func world(_ event: NSEvent) -> Point {
        let p = convert(event.locationInWindow, from: nil)
        return board.viewport.world(Point(p.x, p.y))
    }
    private func screenRect(_ rect: Rect) -> NSRect {
        let p = board.viewport.screen(Point(rect.x, rect.y)), z = board.viewport.zoom
        return NSRect(x: p.x, y: p.y, width: rect.width*z, height: rect.height*z)
    }
    private func invalidate(_ rect: Rect) { setNeedsDisplay(screenRect(rect).insetBy(dx: -5, dy: -5)) }
    private func makePath(_ ink: Ink) -> NSBezierPath {
        let path = NSBezierPath()
        path.lineWidth = ink.width; path.lineCapStyle = .round; path.lineJoinStyle = .round
        if let first = ink.points.first {
            path.move(to: first.cg)
            if ink.points.count == 1 { path.line(to: CGPoint(x: first.x+0.01, y: first.y)) }
            else { for p in ink.points.dropFirst() { path.line(to: p.cg) } }
        }
        return path
    }
    private func drawInk(_ ink: Ink, path: NSBezierPath) {
        NSColor.ink(ink.colour).withAlphaComponent(ink.highlighter ? 0.28 : 1).setStroke()
        path.stroke()
    }
    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        if board.background == "paper" { NSColor.boardPaper.setFill(); dirtyRect.fill() }
        else {
            context.clear(dirtyRect)
            if board.background == "dim" { NSColor.black.withAlphaComponent(0.16).setFill(); dirtyRect.fill() }
        }
        context.saveGState()
        let z = board.viewport.zoom
        context.scaleBy(x: z, y: z)
        context.translateBy(x: -board.viewport.origin.x, y: -board.viewport.origin.y)
        let start = board.viewport.world(Point(dirtyRect.minX, dirtyRect.minY))
        let visible = Rect(start.x, start.y, dirtyRect.width/z, dirtyRect.height/z)
        if board.background == "paper" {
            NSColor.boardInk.withAlphaComponent(0.12).setFill()
            let spacing = z < 0.4 ? 96.0 : 32.0
            for x in stride(from: floor(visible.x/spacing)*spacing, through: visible.x+visible.width, by: spacing) {
                for y in stride(from: floor(visible.y/spacing)*spacing, through: visible.y+visible.height, by: spacing) {
                    NSBezierPath(ovalIn: CGRect(x: x, y: y, width: 1.2/z, height: 1.2/z)).fill()
                }
            }
        }
        let viewportBounds = Rect(board.viewport.origin.x,board.viewport.origin.y,bounds.width/z,bounds.height/z)
        let visibleImages = board.images.filter { ($0.id == croppingID ? $0.frame : $0.visibleFrame).intersects(viewportBounds) }
        if let packageURL {
            images.prepare(visible:visibleImages.map { packageURL.appendingPathComponent("assets").appendingPathComponent($0.asset) })
        }
        for item in visibleImages where (item.id == croppingID ? item.frame : item.visibleFrame).intersects(visible) {
            let displayed = item.id == croppingID ? item.frame : item.visibleFrame
            context.saveGState(); context.clip(to:displayed.cg)
            if let url = packageURL?.appendingPathComponent("assets").appendingPathComponent(item.asset),
               let image = images.image(at: url, ready: { [weak self] in self?.needsDisplay = true }) {
                image.draw(in: item.frame.cg, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: [.interpolation: NSImageInterpolation.medium.rawValue])
            } else {
                NSColor.lightGray.withAlphaComponent(0.3).setFill(); displayed.cg.fill()
                let url = packageURL?.appendingPathComponent("assets").appendingPathComponent(item.asset)
                let label = url.map {images.placeholder(at:$0)} ?? "Image unavailable"
                (label as NSString).draw(at: CGPoint(x: displayed.x+12, y: displayed.y+12), withAttributes: [.font: NSFont.systemFont(ofSize: 14), .foregroundColor: NSColor.secondaryLabelColor])
            }
            context.restoreGState()
            if selected.contains(item.id), croppingID == nil {
                drawSelection(displayed)
                if !item.locked {
                    let side = 8/z
                    NSColor.systemBlue.setFill()
                    NSBezierPath(roundedRect:NSRect(x:displayed.x+displayed.width-side/2,y:displayed.y+displayed.height-side/2,width:side,height:side),xRadius:2/z,yRadius:2/z).fill()
                }
            }
        }
        for ink in board.ink {
            guard let box = boundsByID[ink.id], box.intersects(visible) else { continue }
            let path = paths.object(forKey: ink.id as NSUUID) ?? makePath(ink)
            paths.setObject(path, forKey: ink.id as NSUUID)
            drawInk(ink, path: path)
            if selected.contains(ink.id) { drawSelection(box) }
        }
        for text in board.texts {
            let rect = textRect(text)
            guard rect.intersects(visible), text.id != editingID else { continue }
            (text.text as NSString).draw(in: rect.cg, withAttributes: [.font: NSFont.systemFont(ofSize: text.size), .foregroundColor: NSColor.boardInk])
            if selected.contains(text.id) { drawSelection(rect) }
        }
        if let active, let activePath { drawInk(active, path: activePath) }
        if let selectRect { drawSelection(selectRect) }
        if let id = croppingID, let item = board.images.first(where: {$0.id == id}), let region = cropRegion {
            let mask = NSBezierPath(rect:item.frame.cg); mask.appendRect(region.cg); mask.windingRule = .evenOdd
            NSColor.black.withAlphaComponent(0.38).setFill(); mask.fill()
            NSColor.systemBlue.setStroke(); let border = NSBezierPath(rect:region.cg); border.lineWidth = 2/z; border.stroke()
        }
        context.restoreGState()
        if board.isEmpty && active == nil && editor == nil {
            let text = "A little space for whatever comes to mind."
            let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 23, weight: .medium), .foregroundColor: NSColor.boardInk.withAlphaComponent(0.5)]
            let size = (text as NSString).size(withAttributes: attrs)
            (text as NSString).draw(at: NSPoint(x: max(90, (bounds.width-size.width)/2), y: bounds.height*0.42), withAttributes: attrs)
            let hint = "Write anywhere · Drop a screenshot · Scroll for more space"
            let small: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 13), .foregroundColor: NSColor.boardInk.withAlphaComponent(0.5)]
            let hintSize = (hint as NSString).size(withAttributes: small)
            (hint as NSString).draw(at: NSPoint(x: max(90, (bounds.width-hintSize.width)/2), y: bounds.height*0.42+40), withAttributes: small)
        }
    }
    private func textRect(_ text: BoardText) -> Rect {
        let size = (text.text as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: text.size)])
        return Rect(text.origin.x, text.origin.y, max(80, size.width+8), max(text.size*1.5, size.height+8))
    }
    private func drawSelection(_ rect: Rect) {
        NSColor.systemBlue.withAlphaComponent(0.08).setFill(); rect.cg.fill()
        NSColor.systemBlue.setStroke()
        let path = NSBezierPath(rect: rect.cg.insetBy(dx: -3, dy: -3)); path.lineWidth = 1/board.viewport.zoom; path.stroke()
    }
    override func mouseDown(with event: NSEvent) {
        guard acceptsInput else { return }
        if let id = croppingID, let item = board.images.first(where: {$0.id == id}) {
            let point = world(event)
            if item.frame.contains(point) { cropStart = point; cropRegion = Rect(point.x,point.y,0,0); needsDisplay = true }
            return
        }
        finishEditing(); window?.makeFirstResponder(self)
        let p = world(event); lastPoint = p; gestureStart = p; changedInGesture = false
        panning = tool == .hand || event.modifierFlags.contains(.option)
        if panning { return }
        if tool == .text { startText(at: p); return }
        if tool == .eraser { beginErase(at: p); return }
        if tool == .select {
            if let image = board.images.last(where: {selected.contains($0.id) && !$0.locked && hypot(p.x-$0.visibleFrame.x-$0.visibleFrame.width,p.y-$0.visibleFrame.y-$0.visibleFrame.height) < 12/board.viewport.zoom}) {
                checkpoint(); resizingID = image.id; return
            }
            if let hit = hitObject(p) {
                if event.clickCount == 2, board.images.contains(where: {$0.id == hit && $0.tex != nil}) { onEditTeX?(hit); return }
                if event.clickCount == 2, let text = board.texts.first(where: {$0.id == hit}) { startText(at: text.origin, existing: text); return }
                if !selected.contains(hit) { if !event.modifierFlags.contains(.shift) { selected.removeAll() }; selected.insert(hit) }
                checkpoint(); moving = true
            } else { selected.removeAll(); selectRect = Rect(p.x, p.y, 0, 0) }
            needsDisplay = true; return
        }
        if tool != .shape { checkpoint() }
        let attached = board.images.last(where: {$0.visibleFrame.contains(p)})?.id
        activeShape = tool == .shape ? shape : nil; shapeEnd = p
        keepFreehand = event.modifierFlags.contains(.shift)
        active = Ink(points: [p], colour: colour, width: tool == .highlighter ? 18 : penWidth, highlighter: tool == .highlighter, imageID: attached)
        activePath = makePath(active!); needsDisplay = true
    }
    override func mouseDragged(with event: NSEvent) {
        guard acceptsInput else { return }
        let p = world(event)
        if croppingID != nil { updateCrop(to:p); return }
        if panning, let lastPoint {
            board.viewport.origin.x += lastPoint.x-p.x; board.viewport.origin.y += lastPoint.y-p.y
            needsDisplay = true; onViewChange?(); return
        }
        if let id = resizingID, let image = board.images.first(where: {$0.id == id}) {
            board.resizeImage(id:id,width:max(24,min(20_000,p.x-image.visibleFrame.x)))
            changedInGesture = true; reindex(); needsDisplay = true; return
        }
        if erasing { erase(at: p); return }
        if moving, let previous = lastPoint {
            moveSelection(Point(p.x-previous.x, p.y-previous.y)); lastPoint = p; changedInGesture = true; needsDisplay = true; return
        }
        if selectRect != nil, let start = gestureStart {
            selectRect = Rect(min(p.x,start.x), min(p.y,start.y), abs(p.x-start.x), abs(p.y-start.y)); needsDisplay = true; return
        }
        if activeShape != nil { shapeEnd = p; updateShape(constrained:event.modifierFlags.contains(.shift)); return }
        guard let previous = active?.points.last, hypot(previous.x-p.x, previous.y-p.y)*board.viewport.zoom >= 0.6 else { return }
        active?.points.append(p); activePath?.line(to: p.cg)
        let width = active?.width ?? 3
        invalidate(Rect(min(previous.x,p.x)-width, min(previous.y,p.y)-width, abs(previous.x-p.x)+width*2, abs(previous.y-p.y)+width*2))
    }
    private func updateShape(constrained: Bool) {
        guard let shape = activeShape, let start = gestureStart, let end = shapeEnd, let previous = active else { return }
        active?.points = shape.points(from:start,to:end,constrained:constrained,width:previous.width)
        activePath = makePath(active!); invalidate(previous.bounds); invalidate(active!.bounds)
    }
    override func flagsChanged(with event: NSEvent) {
        if activeShape != nil { updateShape(constrained:event.modifierFlags.contains(.shift)) }
        else { super.flagsChanged(with:event) }
    }
    override func mouseUp(with event: NSEvent) {
        if croppingID != nil { updateCrop(to:world(event)); cropStart = nil; return }
        if activeShape != nil { shapeEnd = world(event); updateShape(constrained:event.modifierFlags.contains(.shift)) }
        if event.modifierFlags.contains(.shift) { keepFreehand = true }
        finishGesture()
    }
    func finishGesture() {
        if activeShape != nil {
            if let start = gestureStart, let end = shapeEnd, hypot(end.x-start.x,end.y-start.y)*board.viewport.zoom >= 3 { checkpoint() }
            else { active = nil; activePath = nil }
        }
        if let active {
            board.ink.append(active); boundsByID[active.id] = active.bounds
            if let activePath { paths.setObject(activePath, forKey: active.id as NSUUID) }
            if automaticShapes, !keepFreehand, activeShape == nil, !active.highlighter,
               let recognised = ShapeRecognition.recognise(active.points,zoom:board.viewport.zoom,width:active.width), recognised.points != active.points {
                // The intermediate checkpoint makes the first Undo restore the actual
                // handwriting; a second Undo removes the stroke, just like normal ink.
                checkpoint()
                var precise = active; precise.points = recognised.points
                board.ink[board.ink.count-1] = precise; boundsByID[precise.id] = precise.bounds
                paths.setObject(makePath(precise),forKey:precise.id as NSUUID)
                onRecognition?(recognised.name)
            }
            self.active = nil; activePath = nil; changedInGesture = true
        }
        activeShape = nil; shapeEnd = nil
        if let rect = selectRect {
            for ink in board.ink where (boundsByID[ink.id]?.intersects(rect) ?? false) { selected.insert(ink.id) }
            for image in board.images where image.visibleFrame.intersects(rect) { selected.insert(image.id) }
            for text in board.texts where textRect(text).intersects(rect) { selected.insert(text.id) }
            selectRect = nil
        }
        if changedInGesture { onEdit?() }
        erasing = false; moving = false; resizingID = nil; panning = false; changedInGesture = false; needsDisplay = true
    }
    override func rightMouseDown(with event: NSEvent) { guard acceptsInput, croppingID == nil else { return }; finishEditing(); beginErase(at: world(event)) }
    override func rightMouseDragged(with event: NSEvent) { guard acceptsInput, croppingID == nil else { return }; erase(at: world(event)) }
    override func rightMouseUp(with event: NSEvent) { finishGesture() }
    private func beginErase(at p: Point) { checkpoint(); erasing = true; changedInGesture = false; erase(at: p) }
    private func erase(at p: Point) {
        let removed = board.ink.filter {$0.hits(p, radius: 9/board.viewport.zoom)}
        guard !removed.isEmpty else { return }
        let ids = Set(removed.map(\.id)); board.ink.removeAll { ids.contains($0.id) }
        for ink in removed { invalidate(ink.bounds); boundsByID.removeValue(forKey: ink.id); paths.removeObject(forKey: ink.id as NSUUID) }
        changedInGesture = true
    }
    private func hitObject(_ p: Point) -> UUID? {
        if let t = board.texts.last(where: {textRect($0).contains(p)}) { return t.id }
        if let ink = board.ink.last(where: {$0.hits(p, radius: 6/board.viewport.zoom)}) { return ink.id }
        return board.images.last(where: {$0.visibleFrame.contains(p)})?.id
    }
    private func moveSelection(_ delta: Point) {
        let movingImages = Set(board.images.filter {selected.contains($0.id) && !$0.locked}.map(\.id))
        for id in movingImages { board.moveImage(id: id, by: delta) }
        for i in board.ink.indices where selected.contains(board.ink[i].id) && !movingImages.contains(board.ink[i].imageID ?? UUID()) {
            board.ink[i].points = board.ink[i].points.map {Point($0.x+delta.x, $0.y+delta.y)}
        }
        for i in board.texts.indices where selected.contains(board.texts[i].id) {
            board.texts[i].origin.x += delta.x; board.texts[i].origin.y += delta.y
        }
        reindex()
    }
    func clearInk() { guard acceptsInput else { return }; finishGesture(); checkpoint(); board.ink.removeAll(); reindex(); onEdit?(); needsDisplay = true }
    func deleteSelection() { guard acceptsInput else { return };
        guard !selected.isEmpty else { return }; checkpoint()
        let removedImages = Set(board.images.filter {selected.contains($0.id)}.map(\.id))
        board.ink.removeAll {selected.contains($0.id) || ($0.imageID.map {removedImages.contains($0)} ?? false)}; board.images.removeAll {selected.contains($0.id)}; board.texts.removeAll {selected.contains($0.id)}
        selected.removeAll(); reindex(); onEdit?(); needsDisplay = true
    }
    override func scrollWheel(with event: NSEvent) {
        guard acceptsInput else { return }
        finishEditing()
        if event.modifierFlags.contains(.command) {
            let p = convert(event.locationInWindow, from: nil)
            board.viewport.zoom(to: board.viewport.zoom * exp(-event.scrollingDeltaY*0.012), at: Point(p.x,p.y))
        } else {
            let factor = event.hasPreciseScrollingDeltas ? 1.0 : 12.0
            board.viewport.origin.x -= event.scrollingDeltaX*factor/board.viewport.zoom
            board.viewport.origin.y -= event.scrollingDeltaY*factor/board.viewport.zoom
        }
        onViewChange?(); needsDisplay = true
    }
    override func magnify(with event: NSEvent) {
        guard acceptsInput else { return }
        let p = convert(event.locationInWindow, from: nil)
        board.viewport.zoom(to: board.viewport.zoom*(1+event.magnification), at: Point(p.x,p.y)); onViewChange?(); needsDisplay = true
    }
    func zoom(_ factor: Double) { guard acceptsInput else { return }; board.viewport.zoom(to: board.viewport.zoom*factor, at: Point(bounds.midX,bounds.midY)); onViewChange?(); needsDisplay = true }
    func duplicateSelection(withAnnotations: Bool = true) { guard acceptsInput else { return };
        finishEditing(); finishGesture(); guard !selected.isEmpty else { return }
        checkpoint(); selected = board.duplicate(selected,withAnnotations:withAnnotations); reindex(); onEdit?(); needsDisplay = true
    }
    func fitContent() { guard acceptsInput else { return };
        finishEditing(); finishGesture()
        let rect = BoardRenderer.contentBounds(board,padding:48)
        let z = min(2,max(0.15,min((bounds.width-180)/rect.width,(bounds.height-240)/rect.height)))
        board.viewport.zoom = z
        board.viewport.origin = Point(rect.x-(bounds.width/z-rect.width)/2,rect.y-180/z)
        onViewChange?(); needsDisplay = true
    }
    func resetView() { guard acceptsInput else { return }; board.viewport = Viewport(); onViewChange?(); needsDisplay = true }
    func freshSpace() { guard acceptsInput else { return };
        let inkBottom = boundsByID.values.map { $0.y + $0.height }.max() ?? 0
        let imageBottom = board.images.map { $0.frame.y + $0.frame.height }.max() ?? 0
        let textBottom = board.texts.map { $0.origin.y + 100 }.max() ?? 0
        let bottom = max(inkBottom, imageBottom, textBottom)
        board.viewport.origin = Point(0, bottom+150); onViewChange?(); needsDisplay = true
    }
    func setBackground(_ background: String) { guard acceptsInput else { return }; board.background = background; onEdit?(); needsDisplay = true }
    private func startText(at p: Point, existing: BoardText? = nil) {
        let field = NSTextField(frame: screenRect(Rect(p.x, p.y, 400, 38)))
        field.font = .systemFont(ofSize: (existing?.size ?? 22)*board.viewport.zoom)
        field.stringValue = existing?.text ?? ""; field.placeholderString = "Your thought…"
        field.delegate = self; field.target = self; field.action = #selector(commitText)
        editingID = existing?.id; gestureStart = p; editor = field; addSubview(field); window?.makeFirstResponder(field); needsDisplay = true
    }
    @objc private func commitText() { finishEditing() }
    func controlTextDidEndEditing(_ obj: Notification) { finishEditing() }
    func finishEditing() {
        guard let field = editor else { return }
        let text = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines), id = editingID
        editor = nil; editingID = nil; field.delegate = nil; field.removeFromSuperview()
        if let id, let i = board.texts.firstIndex(where: {$0.id == id}), text.isEmpty {
            checkpoint(); board.texts.remove(at:i); onEdit?()
        } else if !text.isEmpty && (id == nil || board.texts.first(where: {$0.id == id})?.text != text) {
            checkpoint()
            if let id, let i = board.texts.firstIndex(where: {$0.id == id}) { board.texts[i].text = text }
            else { board.texts.append(BoardText(text: text, origin: gestureStart ?? Point(120,150))) }
            onEdit?()
        }
        window?.makeFirstResponder(self); needsDisplay = true
    }
    override func keyDown(with event: NSEvent) {
        guard acceptsInput else { return }
        if croppingID != nil {
            if event.keyCode == 53 { cancelCrop(); return }
            if event.keyCode == 36 { applyCrop(); return }
            if !event.modifierFlags.contains(.command) { return }
        }
        if event.keyCode == 53, activeShape != nil {
            active = nil; activePath = nil; activeShape = nil; shapeEnd = nil; changedInGesture = false; needsDisplay = true; return
        }
        let key = event.charactersIgnoringModifiers?.lowercased() ?? ""
        if event.modifierFlags.contains(.command) {
            switch key {
            case "v": pasteContent()
            case "c": onCopy?()
            case "d": duplicateSelection()
            case "1": fitContent()
            case "z": event.modifierFlags.contains(.shift) ? redoEdit() : undoEdit()
            case "n": onNew?()
            case "s": finishEditing(); finishGesture(); onEdit?()
            case "e": onExport?()
            case "0": resetView()
            case "=", "+": zoom(1.2)
            case "-": zoom(1/1.2)
            case "a": selected = Set(board.ink.map(\.id)+board.images.map(\.id)+board.texts.map(\.id)); needsDisplay = true
            default: super.keyDown(with: event)
            }
            return
        }
        switch event.keyCode {
        case 53: if selected.isEmpty { onHide?() } else { selected.removeAll(); needsDisplay = true }
        case 51,117: deleteSelection()
        case 36: onRename?()
        default:
            switch key { case "p": tool = .pen; case "h": tool = .highlighter; case "e": tool = .eraser; case "v": tool = .select; case "t": tool = .text; case "c": beginCrop(); case "a": shape = .arrow; tool = .shape; case "l": shape = .line; tool = .shape; case "r": shape = .rectangle; tool = .shape; case "o": shape = .ellipse; tool = .shape; case " ": tool = .hand; default: super.keyDown(with: event) }
        }
    }
    func beginCrop() {
        guard acceptsInput, selected.count == 1, let item = board.images.first(where: {selected.contains($0.id) && !$0.locked && $0.vectorAsset == nil}) else { return }
        finishEditing(); finishGesture(); tool = .select
        croppingID = item.id; cropRegion = item.visibleFrame; cropStart = nil
        onCropChange?(true); needsDisplay = true
    }
    private func updateCrop(to point: Point) {
        guard let id = croppingID, let start = cropStart, let item = board.images.first(where: {$0.id == id}) else { return }
        let x = max(item.frame.x,min(item.frame.x+item.frame.width,point.x)), y = max(item.frame.y,min(item.frame.y+item.frame.height,point.y))
        cropRegion = Rect(min(start.x,x),min(start.y,y),abs(x-start.x),abs(y-start.y)); needsDisplay = true
    }
    func applyCrop() {
        guard acceptsInput, let id = croppingID, let region = cropRegion, min(region.width,region.height)*board.viewport.zoom >= 8 else { NSSound.beep(); return }
        var next = board
        if next.cropImage(id:id,to:region) { checkpoint(); board = next; onEdit?() }
        cancelCrop()
    }
    func cancelCrop() { croppingID = nil; cropRegion = nil; cropStart = nil; onCropChange?(false); needsDisplay = true }
    func restoreImages() {
        guard acceptsInput else { return }; cancelCrop()
        var next = board; var changed = false
        for item in board.images where selected.contains(item.id) { if next.cropImage(id:item.id,to:nil) { changed = true } }
        if changed { checkpoint(); board = next; onEdit?(); needsDisplay = true }
    }
    func pasteContent() {
        let pb = NSPasteboard.general, p = board.viewport.world(Point(bounds.midX-200,bounds.midY-150))
        if let data = pb.data(forType: .png) { onImport?(data,"png",p) }
        else if let data = pb.data(forType: .tiff) { onImport?(data,"tiff",p) }
        else if let text = pb.string(forType: .string) { checkpoint(); board.texts.append(BoardText(text: text, origin: p)); onEdit?(); needsDisplay = true }
    }
    @objc func copy(_ sender: Any?) { guard acceptsInput else { return }; onCopy?() }
    @objc func paste(_ sender: Any?) { guard acceptsInput else { return }; pasteContent() }
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { acceptsInput ? .copy : [] }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard acceptsInput else { return false }; let documentID = board.id
        let p = convert(sender.draggingLocation, from: nil), world = board.viewport.world(Point(p.x,p.y))
        let pb = sender.draggingPasteboard
        if let urls = pb.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] {
            for (i,url) in urls.prefix(8).enumerated() {
                let point = Point(world.x+Double(i)*30,world.y+Double(i)*30)
                DispatchQueue.global(qos: .utility).async { [weak self] in
                    guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= 32*1024*1024,
                          let data = try? Data(contentsOf: url) else { return }
                    DispatchQueue.main.async { guard let self, self.board.id == documentID else { return }; self.onImport?(data,url.pathExtension,point) }
                }
            }
            return true
        }
        if let data = pb.data(forType: .png) ?? pb.data(forType: .tiff) { onImport?(data,pb.data(forType: .png) != nil ? "png" : "tiff",world); return true }
        return false
    }
}
