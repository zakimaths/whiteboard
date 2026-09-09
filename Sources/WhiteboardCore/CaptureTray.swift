import Foundation
import ImageIO

public struct CaptureReference: Codable, Equatable, Identifiable {
    public let id: UUID
    public let title: String
    public let fileExtension: String
    public let width: Double
    public let height: Double
    public let created: Date
}

public enum CaptureTrayError: LocalizedError {
    case full, tooLarge, invalidImage
    public var errorDescription: String? {
        switch self {
        case .full: return "The capture tray is full. Remove a reference before adding another. Placed copies stay on your boards."
        case .tooLarge: return "This image is too large for the capture tray. Use an image file smaller than 32 MiB."
        case .invalidImage: return "This file is not a supported image, or its dimensions are too large."
        }
    }
}

/// Used on the serial storage queue. Keeps compressed originals, never decoded previews.
public final class CaptureTray {
    public static let itemLimit = 8
    public static let byteLimit = 64 * 1024 * 1024
    public static let imageByteLimit = 32 * 1024 * 1024
    public let root: URL
    private let fm = FileManager.default
    private let write: (Data,URL) throws -> Void
    private static let extensions = Set(["png","jpg","jpeg","tiff","heic","gif"])
    public init(libraryRoot: URL, atomicWrite: @escaping (Data,URL) throws -> Void = {try $0.write(to:$1,options:.atomic)}) {
        root = libraryRoot.appendingPathComponent(".capture-tray",isDirectory:true); write = atomicWrite
    }
    private func checkRoot(create: Bool = false) throws -> Bool {
        if fm.fileExists(atPath:root.path) {
            let v = try root.resourceValues(forKeys:[.isDirectoryKey,.isSymbolicLinkKey])
            guard v.isDirectory == true, v.isSymbolicLink != true else { throw BoardError.invalidData }
            return true
        }
        if create { try fm.createDirectory(at:root,withIntermediateDirectories:false); return true }
        return false
    }
    private func package(_ id: UUID) -> URL { root.appendingPathComponent(id.uuidString,isDirectory:true) }
    private func asset(_ reference: CaptureReference) -> URL { package(reference.id).appendingPathComponent("image."+reference.fileExtension) }
    private func regularSize(_ url: URL, limit: Int) throws -> Int {
        let v = try url.resourceValues(forKeys:[.isRegularFileKey,.isSymbolicLinkKey,.fileSizeKey])
        guard v.isRegularFile == true, v.isSymbolicLink != true, let size = v.fileSize, size <= limit else { throw BoardError.invalidData }
        return size
    }
    public func references() throws -> [CaptureReference] {
        guard try checkRoot() else { return [] }
        return try fm.contentsOfDirectory(at:root,includingPropertiesForKeys:[.isDirectoryKey,.isSymbolicLinkKey],options:[.skipsHiddenFiles]).compactMap { url in
            guard let id = UUID(uuidString:url.lastPathComponent) else { return nil }
            let v = try url.resourceValues(forKeys:[.isDirectoryKey,.isSymbolicLinkKey])
            guard v.isDirectory == true, v.isSymbolicLink != true else { throw BoardError.invalidData }
            let metadata = url.appendingPathComponent("reference.json")
            _ = try regularSize(metadata,limit:4096)
            let item = try JSONDecoder().decode(CaptureReference.self,from:Data(contentsOf:metadata))
            guard item.id == id, Self.extensions.contains(item.fileExtension), item.title.count <= 100,
                  item.width.isFinite, item.height.isFinite, item.width > 0, item.height > 0,
                  item.width*item.height <= 100_000_000 else { throw BoardError.invalidData }
            _ = try regularSize(asset(item),limit:Self.imageByteLimit)
            return item
        }.sorted {$0.created == $1.created ? $0.id.uuidString < $1.id.uuidString : $0.created < $1.created}
    }
    @discardableResult public func add(_ data: Data, extension ext: String, title: String) throws -> CaptureReference {
        guard data.count <= Self.imageByteLimit else { throw CaptureTrayError.tooLarge }
        guard Self.extensions.contains(ext.lowercased()),
              let source = CGImageSourceCreateWithData(data as CFData,[kCGImageSourceShouldCache:false] as CFDictionary),
              let properties = CGImageSourceCopyPropertiesAtIndex(source,0,nil) as? [CFString:Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Double,
              let height = properties[kCGImagePropertyPixelHeight] as? Double,
              width > 0, height > 0, width*height <= 100_000_000 else { throw CaptureTrayError.invalidImage }
        let existing = try references()
        let bytes = try existing.reduce(0) {try $0+regularSize(asset($1),limit:Self.imageByteLimit)}
        guard existing.count < Self.itemLimit, data.count <= Self.byteLimit-bytes else { throw CaptureTrayError.full }
        _ = try checkRoot(create:true)
        let item = CaptureReference(id:UUID(),title:Library.safeName(title),fileExtension:ext.lowercased(),width:width,height:height,created:Date())
        let pending = root.appendingPathComponent(".pending-"+item.id.uuidString,isDirectory:true)
        try fm.createDirectory(at:pending,withIntermediateDirectories:false)
        do {
            try write(data,pending.appendingPathComponent("image."+item.fileExtension))
            try write(JSONEncoder().encode(item),pending.appendingPathComponent("reference.json"))
            try fm.moveItem(at:pending,to:package(item.id))
        } catch { try? fm.removeItem(at:pending); throw error }
        return item
    }
    public func data(for id: UUID) throws -> (CaptureReference,Data) {
        guard let item = try references().first(where:{$0.id == id}) else { throw BoardError.missingFile }
        return (item,try Data(contentsOf:asset(item)))
    }
    public func remove(_ id: UUID) throws {
        guard try references().contains(where:{$0.id == id}) else { throw BoardError.missingFile }
        try fm.removeItem(at:package(id))
    }
}
