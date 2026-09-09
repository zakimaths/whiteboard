import Foundation

public struct CaptureReference: Codable, Equatable, Identifiable {
    public let id: UUID
    public let title: String
    public let fileExtension: String
    public let width: Double
    public let height: Double
    public let created: Date
}

public struct CaptureTrayDiagnostic: Equatable {
    public let packageName: String
    public let referenceID: UUID?
    public let message: String
}

public struct CaptureTrayScan: Equatable {
    public let references: [CaptureReference]
    public let diagnostics: [CaptureTrayDiagnostic]
}

public struct CaptureTrayRemoval: Codable, Equatable {
    public let token: UUID
    public let referenceID: UUID
    public let removedAt: Date
}

public enum CaptureTrayError: LocalizedError {
    case full, tooLarge, invalidImage, damaged, undoFull
    public var errorDescription: String? {
        switch self {
        case .full: return "The capture tray is full. Remove a reference before adding another. Placed copies stay on your boards."
        case .tooLarge: return "This image is too large for the capture tray. Use an image file smaller than 32 MiB."
        case .invalidImage: return "This file is not a supported image, or its dimensions are too large."
        case .damaged: return "A capture tray item is damaged. Remove or restore that reported item before adding another reference."
        case .undoFull: return "Removed capture history is full. Restore an item or explicitly empty removed items before removing another."
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
    private func reference(in url: URL, id: UUID) throws -> CaptureReference {
        let v = try url.resourceValues(forKeys:[.isDirectoryKey,.isSymbolicLinkKey])
        guard v.isDirectory == true, v.isSymbolicLink != true else { throw BoardError.invalidData }
        let metadata = url.appendingPathComponent("reference.json")
        _ = try regularSize(metadata,limit:4096)
        let item = try JSONDecoder().decode(CaptureReference.self,from:Data(contentsOf:metadata))
        guard item.id == id, Self.extensions.contains(item.fileExtension), item.title.count <= 100,
              item.width.isFinite, item.height.isFinite, item.width > 0, item.height > 0,
              item.width*item.height <= 100_000_000 else { throw BoardError.invalidData }
        _ = try regularSize(url.appendingPathComponent("image."+item.fileExtension),limit:Self.imageByteLimit)
        return item
    }
    public func scan() throws -> CaptureTrayScan {
        guard try checkRoot() else { return CaptureTrayScan(references:[],diagnostics:[]) }
        var references: [CaptureReference] = [], diagnostics: [CaptureTrayDiagnostic] = []
        for url in try fm.contentsOfDirectory(at:root,includingPropertiesForKeys:[.isDirectoryKey,.isSymbolicLinkKey],options:[.skipsHiddenFiles]) {
            guard let id = UUID(uuidString:url.lastPathComponent) else { continue }
            do { references.append(try reference(in:url,id:id)) }
            catch { diagnostics.append(CaptureTrayDiagnostic(packageName:url.lastPathComponent,referenceID:id,message:error.localizedDescription)) }
        }
        references.sort {$0.created == $1.created ? $0.id.uuidString < $1.id.uuidString : $0.created < $1.created}
        diagnostics.sort {$0.packageName < $1.packageName}
        return CaptureTrayScan(references:references,diagnostics:diagnostics)
    }
    public func references() throws -> [CaptureReference] { try scan().references }
    private func removedEntries() throws -> [(CaptureTrayRemoval,CaptureReference)] {
        guard try checkRoot() else { return [] }
        return try fm.contentsOfDirectory(at:root,includingPropertiesForKeys:[.isDirectoryKey,.isSymbolicLinkKey],options:[]).compactMap { url in
            guard url.lastPathComponent.hasPrefix(".removed-") else { return nil }
            let values = try url.resourceValues(forKeys:[.isDirectoryKey,.isSymbolicLinkKey])
            guard values.isDirectory == true, values.isSymbolicLink != true else { throw CaptureTrayError.damaged }
            guard (try? regularSize(url.appendingPathComponent("removal.json"),limit:4096)) != nil,
                  let removal = try? JSONDecoder().decode(CaptureTrayRemoval.self,from:Data(contentsOf:url.appendingPathComponent("removal.json"))),
                  url.lastPathComponent == ".removed-"+removal.token.uuidString,
                  let item = try? reference(in:url,id:removal.referenceID) else { throw CaptureTrayError.damaged }
            return (removal,item)
        }
    }
    @discardableResult public func add(_ data: Data, extension ext: String, title: String) throws -> CaptureReference {
        guard data.count <= Self.imageByteLimit else { throw CaptureTrayError.tooLarge }
        guard Self.extensions.contains(ext.lowercased()) else { throw CaptureTrayError.invalidImage }
        let image: ImageMetadata
        do { image = try ImageMetadata.inspect(data,byteLimit:Self.imageByteLimit) }
        catch { throw CaptureTrayError.invalidImage }
        let current = try scan()
        guard current.diagnostics.isEmpty else { throw CaptureTrayError.damaged }
        let existing = current.references
        let removed = try removedEntries()
        let activeBytes = try existing.reduce(0) {try $0+regularSize(asset($1),limit:Self.imageByteLimit)}
        let removedBytes = try removed.reduce(0) { total,entry in
            let removedFolder = root.appendingPathComponent(".removed-"+entry.0.token.uuidString,isDirectory:true)
            return try total+regularSize(removedFolder.appendingPathComponent("image."+entry.1.fileExtension),limit:Self.imageByteLimit)
        }
        let bytes = activeBytes + removedBytes
        guard existing.count < Self.itemLimit, data.count <= Self.byteLimit-bytes else { throw CaptureTrayError.full }
        _ = try checkRoot(create:true)
        let item = CaptureReference(id:UUID(),title:Library.safeName(title),fileExtension:ext.lowercased(),width:image.width,height:image.height,created:Date())
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
        guard try checkRoot() else { throw BoardError.missingFile }
        let item = try reference(in:package(id),id:id)
        return (item,try Data(contentsOf:asset(item)))
    }
    @discardableResult public func remove(_ id: UUID) throws -> CaptureTrayRemoval {
        guard try checkRoot() else { throw BoardError.missingFile }
        _ = try reference(in:package(id),id:id)
        return try moveToRemoved(id)
    }
    /// Moves a reported corrupt UUID package aside without deleting it.
    @discardableResult public func removeDamaged(_ id: UUID) throws -> CaptureTrayRemoval {
        guard try checkRoot(), fm.fileExists(atPath:package(id).path) else { throw BoardError.missingFile }
        let values = try package(id).resourceValues(forKeys:[.isDirectoryKey,.isSymbolicLinkKey])
        guard values.isDirectory == true, values.isSymbolicLink != true else { throw BoardError.invalidData }
        return try moveToRemoved(id)
    }
    private func moveToRemoved(_ id: UUID) throws -> CaptureTrayRemoval {
        guard try removedEntries().count < Self.itemLimit else { throw CaptureTrayError.undoFull }
        let removal = CaptureTrayRemoval(token:UUID(),referenceID:id,removedAt:Date())
        try write(JSONEncoder().encode(removal),package(id).appendingPathComponent("removal.json"))
        try fm.moveItem(at:package(id),to:root.appendingPathComponent(".removed-"+removal.token.uuidString,isDirectory:true))
        return removal
    }
    public func restore(_ removal: CaptureTrayRemoval) throws {
        guard try checkRoot() else { throw BoardError.missingFile }
        let current = try scan()
        guard current.references.count+current.diagnostics.count < Self.itemLimit else { throw CaptureTrayError.full }
        let removed = root.appendingPathComponent(".removed-"+removal.token.uuidString,isDirectory:true)
        guard fm.fileExists(atPath:removed.path), !fm.fileExists(atPath:package(removal.referenceID).path) else { throw BoardError.missingFile }
        let values = try removed.resourceValues(forKeys:[.isDirectoryKey,.isSymbolicLinkKey])
        guard values.isDirectory == true, values.isSymbolicLink != true else { throw BoardError.invalidData }
        try fm.moveItem(at:removed,to:package(removal.referenceID))
        try? fm.removeItem(at:package(removal.referenceID).appendingPathComponent("removal.json"))
    }
    @discardableResult public func restoreLastRemoved() throws -> CaptureTrayRemoval {
        guard try checkRoot() else { throw BoardError.missingFile }
        let candidates: [(CaptureTrayRemoval,URL)] = try fm.contentsOfDirectory(at:root,includingPropertiesForKeys:[.isDirectoryKey,.isSymbolicLinkKey],options:[]).compactMap { url in
            guard url.lastPathComponent.hasPrefix(".removed-") else { return nil }
            let values = try url.resourceValues(forKeys:[.isDirectoryKey,.isSymbolicLinkKey])
            guard values.isDirectory == true, values.isSymbolicLink != true else { return nil }
            let metadata = url.appendingPathComponent("removal.json")
            guard (try? regularSize(metadata,limit:4096)) != nil,
                  let removal = try? JSONDecoder().decode(CaptureTrayRemoval.self,from:Data(contentsOf:metadata)),
                  url.lastPathComponent == ".removed-"+removal.token.uuidString else { return nil }
            return (removal,url)
        }
        guard let latest = candidates.max(by:{$0.0.removedAt < $1.0.removedAt}) else { throw BoardError.missingFile }
        try restore(latest.0)
        return latest.0
    }
    /// Permanently clears only already-removed tray packages. Call from an
    /// explicit user action after showing the number of entries to be cleared.
    @discardableResult public func emptyRemoved() throws -> Int {
        guard try checkRoot() else { return 0 }
        let entries = try fm.contentsOfDirectory(at:root,includingPropertiesForKeys:[.isDirectoryKey,.isSymbolicLinkKey],options:[]).filter { $0.lastPathComponent.hasPrefix(".removed-") && UUID(uuidString:String($0.lastPathComponent.dropFirst(9))) != nil }
        for entry in entries {
            let values = try entry.resourceValues(forKeys:[.isDirectoryKey,.isSymbolicLinkKey])
            guard values.isDirectory == true, values.isSymbolicLink != true else { throw BoardError.invalidData }
            try fm.removeItem(at:entry)
        }
        return entries.count
    }
}
