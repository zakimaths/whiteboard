import AppKit
import ImageIO
import Carbon
import WhiteboardCore

final class DirectoryWatch {
    private var source: DispatchSourceFileSystemObject?
    init?(url: URL, changed: @escaping () -> Void) {
        let descriptor = open(url.path, O_EVTONLY)
        guard descriptor >= 0 else { return nil }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: descriptor, eventMask: [.write, .rename, .delete], queue: .main)
        source.setEventHandler(handler: changed)
        source.setCancelHandler { close(descriptor) }
        source.resume()
        self.source = source
    }
    deinit { source?.cancel() }
}

private final class DecodeToken {
    private let lock = NSLock()
    private var cancelled = false
    func cancel() { lock.lock(); cancelled = true; lock.unlock() }
    var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return cancelled }
}

final class ImagePool {
    private var cache: [String: (image: NSImage, cost: Int)] = [:]
    private var desired = Set<String>()
    private var maxPixelSize = 1536
    private var pending = Set<String>()
    private var tokens: [String:DecodeToken] = [:]
    private var failed = Set<String>()
    private var generation = 0
    private let queue = DispatchQueue(label: "Whiteboard.images", qos: .utility)
    func clear() { for token in tokens.values { token.cancel() }; tokens.removeAll(); generation += 1; cache.removeAll(); pending.removeAll(); failed.removeAll(); desired.removeAll() }
    func prepare(visible urls: [URL]) {
        let next = Set(urls.prefix(PreviewBudget.maximumVisibleImages).map(\.path))
        let pixels = PreviewBudget.maxPixelSize(visibleCount: next.count)
        if pixels < maxPixelSize { clear() }
        maxPixelSize = pixels
        cache = cache.filter { next.contains($0.key) }
        failed.formIntersection(next)
        desired = next
    }
    func placeholder(at url: URL) -> String {
        if failed.contains(url.path) { return "Image preview unavailable" }
        return desired.contains(url.path) ? "Loading image…" : "Zoom in to see this preview"
    }
    func image(at url: URL, ready: @escaping () -> Void) -> NSImage? {
        let key = url.path
        if let cached = cache[key] { return cached.image }
        guard desired.contains(key), !pending.contains(url.path), !failed.contains(url.path), pending.count < 4 else { return nil }
        pending.insert(url.path)
        let requestedGeneration = generation, pixels = maxPixelSize
        let token = DecodeToken(); tokens[key] = token
        queue.async {
            guard !token.isCancelled else { return }
            let image: CGImage? = autoreleasepool {
                guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary) else { return nil }
                return CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: pixels, kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceShouldCacheImmediately: true] as CFDictionary)
            }
            DispatchQueue.main.async {
                guard requestedGeneration == self.generation else { return }
                self.pending.remove(url.path); self.tokens.removeValue(forKey:key)
                guard self.desired.contains(key) else { ready(); return }
                let cost = image.map { $0.bytesPerRow * $0.height } ?? 0
                let used = self.cache.values.reduce(0) { $0 + $1.cost }
                if let image, used + cost <= PreviewBudget.bytes {
                    self.cache[key] = (NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height)), cost)
                    ready()
                } else { self.failed.insert(url.path); ready() }
            }
        }
        return nil
    }
    static func dimensions(_ data: Data) -> NSSize? {
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Double,
              let height = properties[kCGImagePropertyPixelHeight] as? Double,
              width > 0, height > 0, width*height <= 100_000_000 else { return nil }
        return NSSize(width: width, height: height)
    }
}

final class HotKey {
    private var reference: EventHotKeyRef?
    private var handler: EventHandlerRef?
    let action: () -> Void
    let released: (() -> Void)?
    let identifier: UInt32
    init(keyCode: UInt32 = UInt32(kVK_ANSI_B), modifiers: UInt32 = UInt32(cmdKey | shiftKey), id: UInt32 = 1, action: @escaping () -> Void, released: (() -> Void)? = nil) {
        self.action = action; self.released = released; identifier = id
        var events = [EventTypeSpec(eventClass:OSType(kEventClassKeyboard),eventKind:UInt32(kEventHotKeyPressed)),EventTypeSpec(eventClass:OSType(kEventClassKeyboard),eventKind:UInt32(kEventHotKeyReleased))]
        let status = InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let context, let event else { return OSStatus(eventNotHandledErr) }
            let owner = Unmanaged<HotKey>.fromOpaque(context).takeUnretainedValue()
            var id = EventHotKeyID()
            guard GetEventParameter(event,EventParamName(kEventParamDirectObject),EventParamType(typeEventHotKeyID),nil,MemoryLayout<EventHotKeyID>.size,nil,&id) == noErr,
                  id.signature == 0x57425244, id.id == owner.identifier else { return OSStatus(eventNotHandledErr) }
            if GetEventKind(event) == UInt32(kEventHotKeyReleased) { owner.released?() } else { owner.action() }
            return noErr
        }, events.count, &events, Unmanaged.passUnretained(self).toOpaque(), &handler)
        guard status == noErr else { return }
        let identifier = EventHotKeyID(signature: 0x57425244, id: id)
        RegisterEventHotKey(keyCode,modifiers,identifier,GetApplicationEventTarget(),0,&reference)
    }
    var registered: Bool { reference != nil }
    deinit { if let reference { UnregisterEventHotKey(reference) }; if let handler { RemoveEventHandler(handler) } }
}

extension Rect { var cg: CGRect { CGRect(x: x, y: y, width: width, height: height) } }
extension Point { var cg: CGPoint { CGPoint(x: x, y: y) } }
extension NSColor {
    static let boardInk = NSColor(calibratedRed: 0.16, green: 0.19, blue: 0.19, alpha: 1)
    static let boardPaper = NSColor(calibratedRed: 0.975, green: 0.969, blue: 0.947, alpha: 1)
    static func ink(_ name: String) -> NSColor {
        switch name { case "blue": return .systemBlue; case "red": return .systemRed; case "green": return .systemGreen; default: return .boardInk }
    }
}
