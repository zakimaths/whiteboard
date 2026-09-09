import AppKit
import WhiteboardCore

enum DrawingTool: String, CaseIterable { case pen, highlighter, eraser, select, text, hand, shape }

private final class CanvasTextEditor: NSTextView {
    var commit: (() -> Void)?
    var cancel: (() -> Void)?
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { cancel?(); return }
        if event.keyCode == 36, event.modifierFlags.contains(.command) { commit?(); return }
        super.keyDown(with:event)
    }
}

private final class CanvasAccessibilityElement: NSAccessibilityElement {
    let objectID: UUID
    var press: (() -> Void)?
    init(id: UUID) { objectID = id; super.init() }
    override func accessibilityPerformPress() -> Bool { press?(); return press != nil }
}

final class CanvasView: NSView, NSTextViewDelegate {
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
    var onImportFiles: (([URL], Point) -> Void)?
    var onHide: (() -> Void)?
    var onStatus: ((String) -> Void)?
    var onNew: (() -> Void)?
    var onRename: (() -> Void)?
    var onExport: (() -> Void)?
    var selected = Set<UUID>()
    let images = ImagePool()
    private let paths = NSCache<NSUUID, NSBezierPath>()
    private var boundsByID: [UUID: Rect] = [:]
    private var inkIndex = SpatialIndex([]), imageIndex = SpatialIndex([]), textIndex = SpatialIndex([])
    private var inkPositions: [UUID:Int] = [:], imagePositions: [UUID:Int] = [:], textPositions: [UUID:Int] = [:]
    private var spatialIndexDirty = false
    private var accessibilityObjects: [UUID: CanvasAccessibilityElement] = [:]
    private var undoStates: [(board: Board, cost: Int)] = [], redoStates: [(board: Board, cost: Int)] = []
    private let undoByteLimit = 32 * 1024 * 1024
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
    private var gestureCheckpointed = false
    private var editor: CanvasTextEditor?
    private var editingID: UUID?
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override var isOpaque: Bool { board.background == "paper" }
    var undoReferencedAssets: Set<String> {
        undoStates.reduce(into: board.referencedAssets) { $0.formUnion($1.board.referencedAssets) }
            .union(redoStates.reduce(into: Set<String>()) { $0.formUnion($1.board.referencedAssets) })
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        paths.countLimit = 512
        registerForDraggedTypes([.fileURL, .png, .tiff])
        setAccessibilityLabel("Whiteboard canvas. Draw, paste a screenshot, or scroll for more space.")
        setAccessibilityRole(.group)
        setAccessibilityHelp("Tab and Shift-Tab move through objects. Arrow keys move a selection; Option-arrow resizes an image. Return edits text or maths.")
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func resetCursorRects() {
        addCursorRect(bounds, cursor: tool == .hand ? .openHand : tool == .text ? .iBeam : .crosshair)
    }
    func load(_ board: Board, at url: URL) {
        finishEditing(); cancelCrop(); self.board = board; packageURL = url
        selected.removeAll(); undoStates.removeAll(); redoStates.removeAll(); images.clear(); paths.removeAllObjects(); accessibilityObjects.removeAll()
        reindex(); needsDisplay = true
    }
    func checkpoint() {
        guard undoStates.last?.board != board else { return }
        undoStates.append((board,board.estimatedMemoryCost))
        trimHistory(&undoStates)
        redoStates.removeAll()
    }
    private func trimHistory(_ states: inout [(board: Board, cost: Int)]) {
        while states.count > 1 && (states.count > 40 || states.reduce(0, {$0+$1.cost}) > undoByteLimit) { states.removeFirst() }
    }
    func undoEdit() { guard acceptsInput else { return };
        if croppingID != nil { cancelCrop(); return }
        finishEditing(); finishGesture(); guard let previous = undoStates.popLast() else { return }
        redoStates.append((board,board.estimatedMemoryCost)); trimHistory(&redoStates); board = previous.board; selected.removeAll(); reindex(); onEdit?(); needsDisplay = true
    }
    func redoEdit() { guard acceptsInput else { return };
        guard let next = redoStates.popLast() else { return }
        undoStates.append((board,board.estimatedMemoryCost)); trimHistory(&undoStates); board = next.board; reindex(); onEdit?(); needsDisplay = true
    }
    func reindex() {
        boundsByID = Dictionary(uniqueKeysWithValues: board.ink.map { ($0.id, $0.bounds) })
        inkIndex = SpatialIndex(board.ink.map { ($0.id,$0.bounds) })
        imageIndex = SpatialIndex(board.images.map { ($0.id,$0.visibleFrame) })
        textIndex = SpatialIndex(board.texts.map { ($0.id,$0.layoutBounds) })
        inkPositions = Dictionary(uniqueKeysWithValues:board.ink.indices.map {(board.ink[$0].id,$0)})
        imagePositions = Dictionary(uniqueKeysWithValues:board.images.indices.map {(board.images[$0].id,$0)})
        textPositions = Dictionary(uniqueKeysWithValues:board.texts.indices.map {(board.texts[$0].id,$0)})
        spatialIndexDirty = false
        paths.removeAllObjects()
        accessibilityObjects = accessibilityObjects.filter { orderedObjectIDs.contains($0.key) }
    }
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
        var visibleImages = spatialIndexDirty ? board.images : imageIndex.ids(intersecting:viewportBounds).compactMap {imagePositions[$0].map {board.images[$0]}}
        if let croppingID, !visibleImages.contains(where:{$0.id == croppingID}), let item = board.images.first(where:{$0.id == croppingID}) { visibleImages.append(item) }
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
                    let side = 16/z
                    NSColor.systemBlue.setFill()
                    NSBezierPath(roundedRect:NSRect(x:displayed.x+displayed.width-side/2,y:displayed.y+displayed.height-side/2,width:side,height:side),xRadius:2/z,yRadius:2/z).fill()
                }
            }
        }
        let visibleInk = spatialIndexDirty ? board.ink : inkIndex.ids(intersecting:visible).compactMap {inkPositions[$0].map {board.ink[$0]}}
        for ink in visibleInk {
            guard let box = boundsByID[ink.id], box.intersects(visible) else { continue }
            let path = paths.object(forKey: ink.id as NSUUID) ?? makePath(ink)
            paths.setObject(path, forKey: ink.id as NSUUID)
            drawInk(ink, path: path)
            if selected.contains(ink.id) { drawSelection(box) }
        }
        let visibleTexts = spatialIndexDirty ? board.texts : textIndex.ids(intersecting:visible).compactMap {textPositions[$0].map {board.texts[$0]}}
        for text in visibleTexts {
            let rect = textRect(text)
            guard rect.intersects(visible), text.id != editingID else { continue }
            let font = NSFont(name:"Helvetica",size:text.size) ?? NSFont.systemFont(ofSize:text.size)
            for (lineIndex,line) in text.lines.enumerated() {
                (line as NSString).draw(at:NSPoint(x:text.origin.x,y:text.origin.y+Double(lineIndex)*text.size*1.25),withAttributes:[.font:font,.foregroundColor:NSColor.boardInk])
            }
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
    private func textRect(_ text: BoardText) -> Rect { text.layoutBounds }
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
        let p = world(event); lastPoint = p; gestureStart = p; changedInGesture = false; gestureCheckpointed = false
        panning = tool == .hand || event.modifierFlags.contains(.option)
        if panning { return }
        if tool == .text { startText(at: p); return }
        if tool == .eraser { beginErase(at: p); return }
        if tool == .select {
            if let image = board.images.last(where: {selected.contains($0.id) && !$0.locked && hypot(p.x-$0.visibleFrame.x-$0.visibleFrame.width,p.y-$0.visibleFrame.y-$0.visibleFrame.height) < 14/board.viewport.zoom}) {
                resizingID = image.id; return
            }
            if let hit = hitObject(p) {
                if event.clickCount == 2, board.images.contains(where: {$0.id == hit && $0.tex != nil}) { onEditTeX?(hit); return }
                if event.clickCount == 2, let text = board.texts.first(where: {$0.id == hit}) { startText(at: text.origin, existing: text); return }
                if !selected.contains(hit) { if !event.modifierFlags.contains(.shift) { selected.removeAll() }; selected.insert(hit) }
                moving = true
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
            let width = max(24,min(20_000,p.x-image.visibleFrame.x))
            guard width != image.visibleFrame.width else { return }
            if !gestureCheckpointed { checkpoint(); gestureCheckpointed = true }
            board.resizeImage(id:id,width:width)
            changedInGesture = true; spatialIndexDirty = true; needsDisplay = true; return
        }
        if erasing { erase(at: p); return }
        if moving, let previous = lastPoint {
            guard canMoveSelection, p != previous else { return }
            if !gestureCheckpointed { checkpoint(); gestureCheckpointed = true }
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
            selected.formUnion(inkIndex.ids(intersecting:rect).filter {boundsByID[$0]?.intersects(rect) ?? false})
            selected.formUnion(imageIndex.ids(intersecting:rect).filter {imagePositions[$0].map {board.images[$0].visibleFrame.intersects(rect)} ?? false})
            selected.formUnion(textIndex.ids(intersecting:rect).filter {textPositions[$0].map {board.texts[$0].layoutBounds.intersects(rect)} ?? false})
            selectRect = nil
        }
        if changedInGesture { reindex(); onEdit?() }
        erasing = false; moving = false; resizingID = nil; panning = false; changedInGesture = false; needsDisplay = true
    }
    override func rightMouseDown(with event: NSEvent) { guard acceptsInput, croppingID == nil else { return }; finishEditing(); beginErase(at: world(event)) }
    override func rightMouseDragged(with event: NSEvent) { guard acceptsInput, croppingID == nil else { return }; erase(at: world(event)) }
    override func rightMouseUp(with event: NSEvent) { finishGesture() }
    private func beginErase(at p: Point) { erasing = true; changedInGesture = false; gestureCheckpointed = false; erase(at: p) }
    private func erase(at p: Point) {
        let removed = board.ink.filter {$0.hits(p, radius: 9/board.viewport.zoom)}
        guard !removed.isEmpty else { return }
        if !gestureCheckpointed { checkpoint(); gestureCheckpointed = true }
        let ids = Set(removed.map(\.id)); board.ink.removeAll { ids.contains($0.id) }
        for ink in removed { invalidate(ink.bounds); boundsByID.removeValue(forKey: ink.id); paths.removeObject(forKey: ink.id as NSUUID) }
        spatialIndexDirty = true; changedInGesture = true
    }
    private func hitObject(_ p: Point) -> UUID? {
        let radius = 6/board.viewport.zoom, query = Rect(p.x-radius,p.y-radius,radius*2,radius*2)
        if let id = textIndex.ids(intersecting:query).reversed().first(where:{textPositions[$0].map {textRect(board.texts[$0]).contains(p)} ?? false}) { return id }
        if let id = inkIndex.ids(intersecting:query).reversed().first(where:{inkPositions[$0].map {board.ink[$0].hits(p,radius:radius)} ?? false}) { return id }
        return imageIndex.ids(intersecting:query).reversed().first(where:{imagePositions[$0].map {board.images[$0].visibleFrame.contains(p)} ?? false})
    }
    private func moveSelection(_ delta: Point) {
        _ = board.moveObjects(selected,by:delta)
        boundsByID = Dictionary(uniqueKeysWithValues:board.ink.map {($0.id,$0.bounds) }); paths.removeAllObjects(); spatialIndexDirty = true
    }
    private var canMoveSelection: Bool { board.hasMovableObjects(selected) }
    func clearInk() {
        guard acceptsInput else { return }; finishGesture()
        let protected = Set(board.images.filter(\.locked).map(\.id))
        guard board.ink.contains(where: {!protected.contains($0.imageID ?? UUID())}) else { return }
        checkpoint(); board.ink.removeAll { !protected.contains($0.imageID ?? UUID()) }; reindex(); onEdit?(); needsDisplay = true
    }
    func deleteSelection() { guard acceptsInput else { return };
        guard !selected.isEmpty else { return }
        var next = board; guard next.deleteObjects(selected) else { return }
        checkpoint(); board = next
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
        let textBottom = board.texts.map { $0.layoutBounds.y + $0.layoutBounds.height }.max() ?? 0
        let bottom = max(inkBottom, imageBottom, textBottom)
        board.viewport.origin = Point(0, bottom+150); onViewChange?(); needsDisplay = true
    }
    func setBackground(_ background: String) { guard acceptsInput else { return }; board.background = background; onEdit?(); needsDisplay = true }
    private func startText(at p: Point, existing: BoardText? = nil) {
        let field = CanvasTextEditor(frame: screenRect(Rect(p.x, p.y, 480, max(90,existing?.layoutBounds.height ?? 110))))
        let fontSize = (existing?.size ?? 22)*board.viewport.zoom
        field.font = NSFont(name:"Helvetica",size:fontSize) ?? .systemFont(ofSize:fontSize)
        field.string = existing?.text ?? ""; field.isRichText = false; field.isVerticallyResizable = true; field.isHorizontallyResizable = false
        field.textContainer?.widthTracksTextView = true; field.textContainerInset = NSSize(width:8,height:7)
        field.drawsBackground = true; field.backgroundColor = NSColor.textBackgroundColor.withAlphaComponent(0.96)
        field.delegate = self; field.commit = { [weak self] in self?.finishEditing() }; field.cancel = { [weak self] in self?.cancelEditing() }
        editingID = existing?.id; gestureStart = p; editor = field; addSubview(field); window?.makeFirstResponder(field); needsDisplay = true
    }
    func textDidEndEditing(_ notification: Notification) { finishEditing() }
    private func cancelEditing() {
        guard let field = editor else { return }; editor = nil; editingID = nil; field.delegate = nil; field.removeFromSuperview(); window?.makeFirstResponder(self); needsDisplay = true
    }
    func finishEditing() {
        guard let field = editor else { return }
        let text = field.string.trimmingCharacters(in: .whitespacesAndNewlines), id = editingID
        editor = nil; editingID = nil; field.delegate = nil; field.removeFromSuperview()
        if let id, let i = board.texts.firstIndex(where: {$0.id == id}), text.isEmpty {
            checkpoint(); board.texts.remove(at:i); reindex(); onEdit?()
        } else if !text.isEmpty && (id == nil || board.texts.first(where: {$0.id == id})?.text != text) {
            checkpoint()
            if let id, let i = board.texts.firstIndex(where: {$0.id == id}) { board.texts[i].text = text }
            else { board.texts.append(BoardText(text: text, origin: gestureStart ?? Point(120,150))) }
            reindex(); onEdit?()
        }
        window?.makeFirstResponder(self); needsDisplay = true
    }
    override func keyDown(with event: NSEvent) {
        guard acceptsInput else { return }
        if croppingID != nil {
            if event.keyCode == 53 { cancelCrop(); return }
            if event.keyCode == 36 { applyCrop(); return }
            if [123,124,125,126].contains(Int(event.keyCode)) { keyboardCrop(keyCode:event.keyCode,move:event.modifierFlags.contains(.option),large:event.modifierFlags.contains(.shift)); return }
            if !event.modifierFlags.contains(.command) { return }
        }
        if event.keyCode == 53, activeShape != nil {
            active = nil; activePath = nil; activeShape = nil; shapeEnd = nil; changedInGesture = false; needsDisplay = true; return
        }
        let key = event.charactersIgnoringModifiers?.lowercased() ?? ""
        if event.keyCode == 48 { selectNextObject(backwards:event.modifierFlags.contains(.shift)); return }
        if [123,124,125,126].contains(Int(event.keyCode)), !selected.isEmpty {
            keyboardTransform(keyCode:event.keyCode,resize:event.modifierFlags.contains(.option),large:event.modifierFlags.contains(.shift)); return
        }
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
        case 36: if !editSelectedObject() { onRename?() }
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
        if next.cropImage(id:id,to:region) { checkpoint(); board = next; reindex(); onEdit?() }
        cancelCrop()
    }
    func cancelCrop() { croppingID = nil; cropRegion = nil; cropStart = nil; onCropChange?(false); needsDisplay = true }
    func restoreImages() {
        guard acceptsInput else { return }; cancelCrop()
        var next = board; var changed = false
        for item in board.images where selected.contains(item.id) { if next.cropImage(id:item.id,to:nil) { changed = true } }
        if changed { checkpoint(); board = next; reindex(); onEdit?(); needsDisplay = true }
    }
    func pasteContent() {
        let pb = NSPasteboard.general, p = board.viewport.world(Point(bounds.midX-200,bounds.midY-150))
        if let data = pb.data(forType: .png) { onImport?(data,"png",p) }
        else if let data = pb.data(forType: .tiff) { onImport?(data,"tiff",p) }
        else if let text = pb.string(forType: .string) { checkpoint(); board.texts.append(BoardText(text: text, origin: p)); reindex(); onEdit?(); needsDisplay = true }
    }
    @objc func copy(_ sender: Any?) { guard acceptsInput else { return }; onCopy?() }
    @objc func paste(_ sender: Any?) { guard acceptsInput else { return }; pasteContent() }
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { acceptsInput ? .copy : [] }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard acceptsInput else { return false }; let documentID = board.id
        let p = convert(sender.draggingLocation, from: nil), world = board.viewport.world(Point(p.x,p.y))
        let pb = sender.draggingPasteboard
        if let urls = pb.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] {
            _ = documentID
            onImportFiles?(urls,world)
            return true
        }
        if let data = pb.data(forType: .png) ?? pb.data(forType: .tiff) { onImport?(data,pb.data(forType: .png) != nil ? "png" : "tiff",world); return true }
        return false
    }

    private var orderedObjectIDs: [UUID] { board.images.map(\.id) + board.ink.map(\.id) + board.texts.map(\.id) }
    func selectNextObject(backwards: Bool) {
        guard acceptsInput else { return }
        let ids = orderedObjectIDs; guard !ids.isEmpty else { return }
        let current = selected.count == 1 ? ids.firstIndex(of:selected.first!) : nil
        let next = current.map { ($0 + (backwards ? ids.count-1 : 1)) % ids.count } ?? (backwards ? ids.count-1 : 0)
        selected = [ids[next]]; needsDisplay = true
        _ = accessibilityChildren()
        NSAccessibility.post(element:accessibilityObjects[ids[next]] ?? self,notification:.focusedUIElementChanged)
    }
    @discardableResult func editSelectedObject() -> Bool {
        guard acceptsInput else { return false }
        guard selected.count == 1, let id = selected.first else { return false }
        if let text = board.texts.first(where:{$0.id == id}) { startText(at:text.origin,existing:text); return true }
        if board.images.contains(where:{$0.id == id && $0.tex != nil}) { onEditTeX?(id); return true }
        return false
    }
    func nudgeSelected(x: Double, y: Double) {
        guard acceptsInput, canMoveSelection, x.isFinite, y.isFinite, x != 0 || y != 0 else { return }
        checkpoint(); moveSelection(Point(x,y)); reindex(); onEdit?(); needsDisplay = true
    }
    func resizeSelected(by delta: Double) {
        guard acceptsInput, delta.isFinite, selected.count == 1, let id = selected.first,
              let image = board.images.first(where:{$0.id == id && !$0.locked}) else { return }
        let width = max(24,min(20_000,image.visibleFrame.width+delta)); guard width != image.visibleFrame.width else { return }
        checkpoint(); board.resizeImage(id:id,width:width); reindex(); onEdit?(); needsDisplay = true
    }
    private func keyboardTransform(keyCode: UInt16, resize: Bool, large: Bool) {
        let amount = large ? 10.0 : 1.0
        if resize {
            let delta = (keyCode == 123 || keyCode == 126) ? -amount : amount
            resizeSelected(by:delta); return
        }
        let delta: Point
        switch keyCode { case 123: delta = Point(-amount,0); case 124: delta = Point(amount,0); case 125: delta = Point(0,amount); default: delta = Point(0,-amount) }
        nudgeSelected(x:delta.x,y:delta.y)
    }
    private func keyboardCrop(keyCode: UInt16, move: Bool, large: Bool) {
        guard let id = croppingID, let image = board.images.first(where:{$0.id == id}), var region = cropRegion else { return }
        let amount = (large ? 10.0 : 1.0) / board.viewport.zoom
        if move {
            switch keyCode {
            case 123: region.x = max(image.frame.x,region.x-amount)
            case 124: region.x = min(image.frame.x+image.frame.width-region.width,region.x+amount)
            case 126: region.y = max(image.frame.y,region.y-amount)
            default: region.y = min(image.frame.y+image.frame.height-region.height,region.y+amount)
            }
        } else {
            switch keyCode {
            case 123: region.width = max(amount,region.width-amount)
            case 124: region.width = min(image.frame.x+image.frame.width-region.x,region.width+amount)
            case 126: region.height = max(amount,region.height-amount)
            default: region.height = min(image.frame.y+image.frame.height-region.y,region.height+amount)
            }
        }
        cropRegion = region; needsDisplay = true
    }

    override func accessibilityChildren() -> [Any]? {
        var children: [NSAccessibilityElement] = []
        func add(_ id: UUID, _ role: NSAccessibility.Role, _ label: String, _ rect: Rect) {
            let element = accessibilityObjects[id] ?? CanvasAccessibilityElement(id:id)
            accessibilityObjects[id] = element; element.press = { [weak self, weak element] in
                guard let self, self.acceptsInput else { return }
                self.selected = [id]; self.window?.makeFirstResponder(self); self.needsDisplay = true
                if let element { NSAccessibility.post(element:element,notification:.focusedUIElementChanged) }
            }
            element.setAccessibilityParent(self); element.setAccessibilityRole(role); element.setAccessibilityLabel(label)
            element.setAccessibilityIdentifier(id.uuidString); element.setAccessibilitySelected(selected.contains(id)); element.setAccessibilityFocused(selected.contains(id))
            element.setAccessibilityCustomActions([NSAccessibilityCustomAction(name:"Edit") { [weak self] in
                self?.selected = [id]; return self?.editSelectedObject() ?? false
            }])
            let local = screenRect(rect), windowRect = convert(local,to:nil), screen = window?.convertToScreen(windowRect) ?? windowRect
            element.setAccessibilityFrame(screen); children.append(element)
        }
        for image in board.images { add(image.id,.image,image.accessibilityDescription ?? (image.tex == nil ? "Image" : (image.tex?.kind == .latex ? "Editable LaTeX equation" : "Editable TikZ diagram")),image.visibleFrame) }
        for ink in board.ink { add(ink.id,.group,ink.highlighter ? "Highlighter stroke" : "\(ink.colour) ink stroke",ink.bounds) }
        for text in board.texts { add(text.id,.staticText,text.text,text.layoutBounds) }
        if let editor { return children + [editor] }
        return children
    }
}
