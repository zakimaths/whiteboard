import Foundation
import CoreText

public struct Point: Codable, Equatable {
    public var x: Double
    public var y: Double
    public init(_ x: Double, _ y: Double) { self.x = x; self.y = y }
}

public struct Rect: Codable, Equatable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double
    public init(_ x: Double, _ y: Double, _ width: Double, _ height: Double) {
        self.x = x; self.y = y; self.width = width; self.height = height
    }
    public func contains(_ p: Point, padding: Double = 0) -> Bool {
        p.x >= x-padding && p.x <= x+width+padding && p.y >= y-padding && p.y <= y+height+padding
    }
    public func intersects(_ r: Rect) -> Bool {
        x <= r.x+r.width && x+width >= r.x && y <= r.y+r.height && y+height >= r.y
    }
}

public struct Ink: Codable, Equatable, Identifiable {
    public var id: UUID = UUID()
    public var points: [Point]
    public var colour: String
    public var width: Double
    public var highlighter: Bool
    public var imageID: UUID?
    public init(points: [Point], colour: String = "ink", width: Double = 3, highlighter: Bool = false, imageID: UUID? = nil) {
        self.points = points; self.colour = colour; self.width = width; self.highlighter = highlighter; self.imageID = imageID
    }
    public var bounds: Rect {
        guard let first = points.first else { return Rect(0, 0, 0, 0) }
        var minX = first.x, maxX = first.x, minY = first.y, maxY = first.y
        for p in points { minX = min(minX, p.x); maxX = max(maxX, p.x); minY = min(minY, p.y); maxY = max(maxY, p.y) }
        return Rect(minX-width, minY-width, maxX-minX+width*2, maxY-minY+width*2)
    }
    public func hits(_ p: Point, radius: Double) -> Bool {
        guard bounds.contains(p, padding: radius) else { return false }
        let threshold = radius + width/2
        if points.isEmpty { return false }
        if points.count == 1 { return hypot(points[0].x-p.x, points[0].y-p.y) <= threshold }
        for i in 1..<points.count {
            let a = points[i-1], b = points[i]
            let dx = b.x-a.x, dy = b.y-a.y, length = dx*dx+dy*dy
            let t = length == 0 ? 0 : max(0, min(1, ((p.x-a.x)*dx+(p.y-a.y)*dy)/length))
            if hypot(p.x-a.x-t*dx, p.y-a.y-t*dy) <= threshold { return true }
        }
        return false
    }
}

public struct BoardImage: Codable, Equatable, Identifiable {
    public var id: UUID = UUID()
    public var asset: String
    public var frame: Rect
    public var locked: Bool = false
    public var tex: TeXSource?
    public var vectorAsset: String?
    public var accessibilityDescription: String?
    /// Normalised source-image region, measured from its top-left. Original assets stay intact.
    public var crop: Rect?
    public init(asset: String, frame: Rect) { self.asset = asset; self.frame = frame }
    public var visibleFrame: Rect {
        guard let crop else { return frame }
        return Rect(frame.x+crop.x*frame.width,frame.y+crop.y*frame.height,frame.width*crop.width,frame.height*crop.height)
    }
}

public struct BoardText: Codable, Equatable, Identifiable {
    public var id: UUID = UUID()
    public var text: String
    public var origin: Point
    public var size: Double = 22
    public init(text: String, origin: Point) { self.text = text; self.origin = origin }
    public var lines: [String] { text.components(separatedBy: "\n") }
    /// Shared sizing rules for canvas hit testing and document rendering.
    public var layoutBounds: Rect {
        let font = CTFontCreateWithName("Helvetica" as CFString,size,nil)
        let widest = lines.map { line -> Double in
            let attributes = [kCTFontAttributeName:font] as CFDictionary
            let value = CFAttributedStringCreate(nil,line as CFString,attributes)!
            return CTLineGetTypographicBounds(CTLineCreateWithAttributedString(value),nil,nil,nil)
        }.max() ?? 0
        return Rect(origin.x,origin.y,max(80,ceil(widest)+8),max(size*1.5,Double(lines.count)*size*1.25+8))
    }
}

public struct Viewport: Codable, Equatable {
    public var origin: Point = Point(0, 0)
    public var zoom: Double = 1
    public init() {}
    public func world(_ p: Point) -> Point { Point(origin.x+p.x/zoom, origin.y+p.y/zoom) }
    public func screen(_ p: Point) -> Point { Point((p.x-origin.x)*zoom, (p.y-origin.y)*zoom) }
    public mutating func zoom(to value: Double, at anchor: Point) {
        let before = world(anchor)
        zoom = max(0.15, min(4, value))
        origin = Point(before.x-anchor.x/zoom, before.y-anchor.y/zoom)
    }
}

public struct Board: Codable, Equatable {
    public var version: Int = 1
    public var id: UUID = UUID()
    public var ink: [Ink] = []
    public var images: [BoardImage] = []
    public var texts: [BoardText] = []
    public var viewport = Viewport()
    public var background: String = "transparent"
    public var recognisedText: String = ""
    public init() {}
    public var isEmpty: Bool { ink.isEmpty && images.isEmpty && texts.isEmpty }
    /// Conservative in-memory estimate used to bound interactive undo history.
    public var estimatedMemoryCost: Int {
        let points = ink.reduce(0) { $0 + $1.points.count * MemoryLayout<Point>.stride }
        let objects = ink.count * 128 + images.count * 512 + texts.count * 128
        let textBytes = texts.reduce(0) { $0 + $1.text.utf8.count }
        let imageBytes = images.reduce(0) { partial, image in
            partial + image.asset.utf8.count + (image.vectorAsset?.utf8.count ?? 0) + (image.tex?.code.utf8.count ?? 0)
        }
        let strings = textBytes + recognisedText.utf8.count + imageBytes
        return max(1, points + objects + strings + 1024)
    }
    public var referencedAssets: Set<String> {
        Set(images.flatMap { [$0.asset] + ($0.vectorAsset.map { [$0] } ?? []) })
    }
    public func hasMovableObjects(_ ids: Set<UUID>) -> Bool {
        let lockedImages = Set(images.filter(\.locked).map(\.id))
        return images.contains { ids.contains($0.id) && !$0.locked }
            || ink.contains { ids.contains($0.id) && !lockedImages.contains($0.imageID ?? UUID()) }
            || texts.contains { ids.contains($0.id) }
    }
    @discardableResult public mutating func moveObjects(_ ids: Set<UUID>, by delta: Point) -> Bool {
        guard delta.x.isFinite, delta.y.isFinite, delta.x != 0 || delta.y != 0, hasMovableObjects(ids) else { return false }
        let lockedImages = Set(images.filter(\.locked).map(\.id))
        let movingImages = Set(images.filter {ids.contains($0.id) && !$0.locked}.map(\.id))
        for id in movingImages { moveImage(id:id,by:delta) }
        for i in ink.indices where ids.contains(ink[i].id) && !movingImages.contains(ink[i].imageID ?? UUID()) && !lockedImages.contains(ink[i].imageID ?? UUID()) {
            ink[i].points = ink[i].points.map {Point($0.x+delta.x,$0.y+delta.y)}
        }
        for i in texts.indices where ids.contains(texts[i].id) { texts[i].origin = Point(texts[i].origin.x+delta.x,texts[i].origin.y+delta.y) }
        return true
    }
    @discardableResult public mutating func deleteObjects(_ ids: Set<UUID>) -> Bool {
        let lockedImages = Set(images.filter(\.locked).map(\.id))
        let removedImages = Set(images.filter {ids.contains($0.id) && !$0.locked}.map(\.id))
        let removedInk = Set(ink.filter { (ids.contains($0.id) && !lockedImages.contains($0.imageID ?? UUID())) || ($0.imageID.map {removedImages.contains($0)} ?? false) }.map(\.id))
        let removedText = Set(texts.filter {ids.contains($0.id)}.map(\.id))
        guard !removedImages.isEmpty || !removedInk.isEmpty || !removedText.isEmpty else { return false }
        ink.removeAll {removedInk.contains($0.id)}; images.removeAll {removedImages.contains($0.id)}; texts.removeAll {removedText.contains($0.id)}
        return true
    }
    public mutating func moveImage(id: UUID, by delta: Point) {
        guard let i = images.firstIndex(where: { $0.id == id }), !images[i].locked else { return }
        images[i].frame.x += delta.x; images[i].frame.y += delta.y
        for j in ink.indices where ink[j].imageID == id {
            ink[j].points = ink[j].points.map { Point($0.x+delta.x, $0.y+delta.y) }
        }
    }
    public mutating func resizeImage(id: UUID, width: Double) {
        guard let i = images.firstIndex(where: {$0.id == id}), !images[i].locked,
              width.isFinite, width >= 24, width <= 20_000 else { return }
        let old = images[i].frame, anchor = images[i].visibleFrame, scale = width / anchor.width
        guard scale.isFinite, (old.width*scale).isFinite, (old.height*scale).isFinite else { return }
        images[i].frame.x = anchor.x+(old.x-anchor.x)*scale
        images[i].frame.y = anchor.y+(old.y-anchor.y)*scale
        images[i].frame.height *= scale
        images[i].frame.width = old.width*scale
        for j in ink.indices where ink[j].imageID == id {
            ink[j].points = ink[j].points.map {Point(anchor.x+($0.x-anchor.x)*scale, anchor.y+($0.y-anchor.y)*scale)}
            ink[j].width = min(200, max(0.1, ink[j].width*scale))
        }
    }
    @discardableResult public mutating func cropImage(id: UUID, to region: Rect?) -> Bool {
        guard let i = images.firstIndex(where: {$0.id == id}), !images[i].locked, images[i].vectorAsset == nil else { return false }
        guard let region else { let changed = images[i].crop != nil; images[i].crop = nil; return changed }
        guard [region.x,region.y,region.width,region.height].allSatisfy({$0.isFinite}), region.width > 0, region.height > 0 else { return false }
        let frame = images[i].frame
        let x = max(frame.x,region.x), y = max(frame.y,region.y)
        let right = min(frame.x+frame.width,region.x+region.width), bottom = min(frame.y+frame.height,region.y+region.height)
        guard right > x, bottom > y else { return false }
        let crop = Rect(max(0,(x-frame.x)/frame.width),max(0,(y-frame.y)/frame.height),min(1,(right-x)/frame.width),min(1,(bottom-y)/frame.height))
        let value: Rect? = crop == Rect(0,0,1,1) ? nil : crop
        guard images[i].crop != value else { return false }
        images[i].crop = value
        if value != nil { version = 2 }
        return true
    }
    public func selection(_ ids: Set<UUID>) -> Board {
        var result = self; result.id = UUID()
        result.images = images.filter {ids.contains($0.id)}
        let imageIDs = Set(result.images.map(\.id))
        result.ink = ink.filter {ids.contains($0.id) || ($0.imageID.map {imageIDs.contains($0)} ?? false)}
        for i in result.ink.indices where !imageIDs.contains(result.ink[i].imageID ?? UUID()) { result.ink[i].imageID = nil }
        result.texts = texts.filter {ids.contains($0.id)}
        result.recognisedText = ""
        return result
    }
    @discardableResult public mutating func duplicate(_ ids: Set<UUID>, withAnnotations: Bool = true, offset: Point = Point(36,36)) -> Set<UUID> {
        var copy = selection(ids)
        var imageIDs: [UUID:UUID] = [:]
        for i in copy.images.indices {
            let original = copy.images[i].id; copy.images[i].id = UUID(); copy.images[i].locked = false
            imageIDs[original] = copy.images[i].id
            copy.images[i].frame.x += offset.x; copy.images[i].frame.y += offset.y
        }
        if !withAnnotations { copy.ink.removeAll {$0.imageID != nil} }
        for i in copy.ink.indices {
            copy.ink[i].id = UUID(); copy.ink[i].imageID = copy.ink[i].imageID.flatMap {imageIDs[$0]}
            copy.ink[i].points = copy.ink[i].points.map {Point($0.x+offset.x,$0.y+offset.y)}
        }
        for i in copy.texts.indices { copy.texts[i].id = UUID(); copy.texts[i].origin.x += offset.x; copy.texts[i].origin.y += offset.y }
        images += copy.images; ink += copy.ink; texts += copy.texts
        return Set(copy.images.map(\.id)+copy.ink.map(\.id)+copy.texts.map(\.id))
    }
    public func validated() throws -> Board {
        guard version == 1 || version == 2 else { throw BoardError.unsupportedVersion }
        guard viewport.zoom.isFinite, (0.15...4).contains(viewport.zoom),
              viewport.origin.x.isFinite, viewport.origin.y.isFinite,
              ink.count <= 100_000, images.count <= 10_000, texts.count <= 50_000 else { throw BoardError.invalidData }
        let ids = ink.map(\.id) + images.map(\.id) + texts.map(\.id)
        guard Set(ids).count == ids.count else { throw BoardError.invalidData }
        for stroke in ink {
            guard !stroke.points.isEmpty, stroke.points.count <= 1_000_000,
                  stroke.width.isFinite, stroke.width > 0, stroke.width <= 200,
                  stroke.points.allSatisfy({ $0.x.isFinite && $0.y.isFinite }) else { throw BoardError.invalidData }
        }
        for image in images {
            guard image.asset == URL(fileURLWithPath: image.asset).lastPathComponent,
                  !image.asset.contains(".."), !image.asset.isEmpty,
                  [image.frame.x,image.frame.y,image.frame.width,image.frame.height].allSatisfy({$0.isFinite}),
                  image.frame.width > 0, image.frame.height > 0 else { throw BoardError.invalidData }
            if let asset = image.vectorAsset {
                guard asset == URL(fileURLWithPath:asset).lastPathComponent, !asset.contains(".."), !asset.isEmpty else { throw BoardError.invalidData }
            }
            if let tex = image.tex { guard tex.code.utf8.count <= 64*1024 else { throw BoardError.invalidData } }
            if let description = image.accessibilityDescription { guard description.utf8.count <= 2_000 else { throw BoardError.invalidData } }
            if let crop = image.crop {
                guard version >= 2, image.vectorAsset == nil, [crop.x,crop.y,crop.width,crop.height].allSatisfy({$0.isFinite}),
                      crop.x >= 0, crop.y >= 0, crop.width > 0, crop.height > 0,
                      crop.x+crop.width <= 1.000000001, crop.y+crop.height <= 1.000000001 else { throw BoardError.invalidData }
            }
        }
        for text in texts {
            guard text.origin.x.isFinite, text.origin.y.isFinite, text.size.isFinite,
                  (1...500).contains(text.size) else { throw BoardError.invalidData }
        }
        return self
    }
}

public enum BoardError: LocalizedError {
    case unsupportedVersion, invalidData, conflict, missingFile
    public var errorDescription: String? {
        switch self {
        case .unsupportedVersion: return "This board uses a newer file format. It has not been changed."
        case .invalidData: return "This file is not a valid whiteboard. It has not been changed."
        case .conflict: return "This board changed outside Whiteboard. Save a copy before continuing."
        case .missingFile: return "This board was moved or removed outside Whiteboard. Save a copy to keep your changes."
        }
    }
}
