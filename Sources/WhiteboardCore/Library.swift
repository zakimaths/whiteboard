import Foundation
import CryptoKit

public enum IdeaStatus: String, CaseIterable { case unfinished = "Unfinished", finished = "Finished", archived = "Archive" }

public struct ShelfItem: Equatable {
    public var url: URL
    public var status: IdeaStatus
    public var modified: Date
    public var title: String { url.deletingPathExtension().lastPathComponent }
    public init(url: URL, status: IdeaStatus, modified: Date) { self.url = url; self.status = status; self.modified = modified }
}

public struct RecoverySnapshot: Equatable {
    public let filename: String
    public let date: Date
    public let bytes: Int
}

// All operations are run on the application's single storage queue.
public final class Library {
    public let root: URL
    private let fm = FileManager.default
    private var knownVersions: [URL: MetadataVersion] = [:]
    private let write: (Data,URL) throws -> Void
    private let now: () -> Date
    private var nextSnapshot: [URL: Date] = [:]
    public static let historyLimit = 20
    public static let historyByteLimit = 64 * 1024 * 1024
    public init(root: URL, now: @escaping () -> Date = Date.init, atomicWrite: @escaping (Data,URL) throws -> Void = {try $0.write(to:$1,options:.atomic)}) throws {
        self.root = root.standardizedFileURL
        self.write = atomicWrite; self.now = now
        for status in IdeaStatus.allCases {
            try fm.createDirectory(at: folder(status), withIntermediateDirectories: true)
        }
    }
    public func folder(_ status: IdeaStatus) -> URL { root.appendingPathComponent(status.rawValue, isDirectory: true) }
    public static func safeName(_ name: String) -> String {
        let forbidden = CharacterSet(charactersIn: "/:\\").union(.controlCharacters)
        let cleaned = name.components(separatedBy: forbidden).joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty || cleaned == "." || cleaned == ".." ? "Untitled idea" : String(cleaned.prefix(100))
    }
    public func availableURL(name: String, status: IdeaStatus) -> URL {
        let base = Self.safeName(name)
        var result = folder(status).appendingPathComponent(base).appendingPathExtension("whiteboard")
        var suffix = 2
        while fm.fileExists(atPath: result.path) {
            result = folder(status).appendingPathComponent("\(base) \(suffix)").appendingPathExtension("whiteboard")
            suffix += 1
        }
        return URL(fileURLWithPath:result.path,isDirectory:true)
    }
    public func create(name: String = "Untitled idea", board: Board = Board()) throws -> URL {
        let url = availableURL(name: name, status: .unfinished)
        try fm.createDirectory(at: url.appendingPathComponent("assets"), withIntermediateDirectories: true)
        do { try save(board, at: url, checkingVersion: false) }
        catch { try? fm.removeItem(at:url); throw error }
        return url
    }
    public func list() throws -> [ShelfItem] {
        var result: [ShelfItem] = []
        for status in IdeaStatus.allCases {
            for url in try fm.contentsOfDirectory(at: folder(status), includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey, .contentModificationDateKey], options: [.skipsHiddenFiles]) where url.pathExtension == "whiteboard" {
                let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey, .contentModificationDateKey])
                guard values.isDirectory == true, values.isSymbolicLink != true else { continue }
                // Directory enumeration may resolve /var to /private/var. Keep the
                // chosen root's spelling so file identity matches create/move/load.
                let itemURL = folder(status).appendingPathComponent(url.lastPathComponent,isDirectory:true)
                result.append(ShelfItem(url: itemURL, status: status, modified: values.contentModificationDate ?? .distantPast))
            }
        }
        return result.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }
    private struct MetadataVersion: Equatable {
        let bytes: Int
        let digest: Digest256
    }
    private func metadata(_ url: URL) throws -> (Data,MetadataVersion) {
        guard fm.fileExists(atPath:url.path) else { throw BoardError.missingFile }
        let data = try readMetadata(url)
        return (data,MetadataVersion(bytes:data.count,digest:Digest256(data)))
    }
    private func encode(_ board: Board) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(board)
    }
    public func load(_ url: URL) throws -> Board {
        let file = url.appendingPathComponent("board.json")
        let (data,version) = try metadata(file)
        let result = try JSONDecoder().decode(Board.self, from:data).validated()
        knownVersions[url] = version
        return result
    }
    public func save(_ board: Board, at url: URL, checkingVersion: Bool = true) throws {
        _ = try board.validated()
        let file = url.appendingPathComponent("board.json")
        guard fm.fileExists(atPath: url.path) else { throw BoardError.missingFile }
        let existing: Data?
        if fm.fileExists(atPath:file.path) {
            let value = try metadata(file)
            if checkingVersion, let known = knownVersions[url], value.1 != known { throw BoardError.conflict }
            existing = value.0
        } else {
            if checkingVersion { throw BoardError.missingFile }
            existing = nil
        }
        let data = try encode(board)
        guard data.count < 64*1024*1024 else { throw BoardError.invalidData }
        if let existing, data == existing {
            knownVersions[url] = MetadataVersion(bytes:data.count,digest:Digest256(data))
            return
        }
        // Keep one recoverable previous version. Never move away the current valid file.
        if let previous = existing {
            if nextSnapshot[url] == nil {
                nextSnapshot[url] = try history(url).first.map {$0.date.addingTimeInterval(300)} ?? .distantPast
            }
            if now() >= nextSnapshot[url]! {
                _ = try JSONDecoder().decode(Board.self,from:previous).validated()
                try storeSnapshot(previous,at:url)
            }
            try write(previous,url.appendingPathComponent("previous.json"))
        }
        try write(data,file)
        knownVersions[url] = MetadataVersion(bytes:data.count,digest:Digest256(data))
    }
    private func readMetadata(_ file: URL) throws -> Data {
        let values = try file.resourceValues(forKeys:[.fileSizeKey,.isRegularFileKey,.isSymbolicLinkKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true,
              let size = values.fileSize, size < Self.historyByteLimit else { throw BoardError.invalidData }
        return try Data(contentsOf:file)
    }
    private func historyFolder(_ url: URL, create: Bool = false) throws -> URL {
        let folder = url.appendingPathComponent("history",isDirectory:true)
        if fm.fileExists(atPath:folder.path) {
            let values = try folder.resourceValues(forKeys:[.isDirectoryKey,.isSymbolicLinkKey])
            guard values.isDirectory == true, values.isSymbolicLink != true else { throw BoardError.invalidData }
        } else if create { try fm.createDirectory(at:folder,withIntermediateDirectories:false) }
        return folder
    }
    /// Lists file metadata only; no board or image decoding and no background timer.
    public func history(_ url: URL) throws -> [RecoverySnapshot] {
        let folder = try historyFolder(url)
        guard fm.fileExists(atPath:folder.path) else { return [] }
        return try fm.contentsOfDirectory(at:folder,includingPropertiesForKeys:[.fileSizeKey,.isRegularFileKey,.isSymbolicLinkKey],options:[.skipsHiddenFiles]).compactMap { file in
            let parts = file.deletingPathExtension().lastPathComponent.split(separator:"_")
            guard file.pathExtension == "json", parts.count == 2, UUID(uuidString:String(parts[1])) != nil,
                  let time = Double(parts[0]), time.isFinite else { return nil }
            let values = try file.resourceValues(forKeys:[.fileSizeKey,.isRegularFileKey,.isSymbolicLinkKey])
            guard values.isRegularFile == true, values.isSymbolicLink != true, let size = values.fileSize else { return nil }
            return RecoverySnapshot(filename:file.lastPathComponent,date:Date(timeIntervalSince1970:time),bytes:size)
        }.sorted { $0.date == $1.date ? $0.filename > $1.filename : $0.date > $1.date }
    }
    private func storeSnapshot(_ data: Data, at url: URL) throws {
        let folder = try historyFolder(url,create:true), date = now()
        let filename = String(format:"%.6f",locale:Locale(identifier:"en_US_POSIX"),date.timeIntervalSince1970)+"_"+UUID().uuidString+".json"
        try write(data,folder.appendingPathComponent(filename))
        // Prune only after the new snapshot exists. Assets remain shared with the board.
        var bytes = 0
        for (index,snapshot) in try history(url).enumerated() {
            bytes += snapshot.bytes
            if index >= Self.historyLimit || bytes > Self.historyByteLimit {
                try fm.removeItem(at:folder.appendingPathComponent(snapshot.filename))
            }
        }
        nextSnapshot[url] = date.addingTimeInterval(300)
    }
    public func checkpoint(_ url: URL) throws {
        let file = url.appendingPathComponent("board.json")
        let (data,version) = try metadata(file)
        if let known = knownVersions[url], version != known { throw BoardError.conflict }
        _ = try JSONDecoder().decode(Board.self,from:data).validated()
        try storeSnapshot(data,at:url)
    }
    public func recoverSnapshot(_ filename: String, from url: URL) throws -> URL {
        guard try history(url).contains(where: {$0.filename == filename}) else { throw BoardError.missingFile }
        let file = try historyFolder(url).appendingPathComponent(filename)
        var board = try JSONDecoder().decode(Board.self,from:readMetadata(file)).validated()
        board.id = UUID()
        return try copy(board,from:url,name:url.deletingPathExtension().lastPathComponent+" recovered")
    }
    public func recoverPrevious(_ url: URL) throws -> URL {
        let previous = url.appendingPathComponent("previous.json")
        guard let size = try previous.resourceValues(forKeys:[.fileSizeKey]).fileSize, size < 64*1024*1024 else { throw BoardError.invalidData }
        var board = try JSONDecoder().decode(Board.self,from:Data(contentsOf:previous)).validated()
        board.id = UUID()
        return try copy(board,from:url,name:url.deletingPathExtension().lastPathComponent+" recovered")
    }
    public func move(_ url: URL, to status: IdeaStatus, name: String? = nil) throws -> URL {
        if url.deletingLastPathComponent() == folder(status), name == nil { return url }
        let title = name ?? url.deletingPathExtension().lastPathComponent
        let candidate = URL(fileURLWithPath:folder(status).appendingPathComponent(Self.safeName(title)).appendingPathExtension("whiteboard").path,isDirectory:true)
        if candidate == url { return url }
        let destination = availableURL(name: title, status: status)
        try fm.moveItem(at: url, to: destination)
        knownVersions[destination] = knownVersions.removeValue(forKey: url)
        nextSnapshot[destination] = nextSnapshot.removeValue(forKey:url)
        return destination
    }
    public func copy(_ board: Board, from source: URL, name: String) throws -> URL {
        let destination = try create(name: name, board: board)
        do {
            let assets = Set(board.images.flatMap { [$0.asset] + ($0.vectorAsset.map {[$0]} ?? []) })
            for asset in assets {
                let src = source.appendingPathComponent("assets").appendingPathComponent(asset)
                let dst = destination.appendingPathComponent("assets").appendingPathComponent(asset)
                if !fm.fileExists(atPath: dst.path) { try fm.copyItem(at: src, to: dst) }
            }
        } catch {
            try? fm.removeItem(at: destination)
            throw error
        }
        return destination
    }
    public func importAsset(data: Data, extension ext: String, to url: URL) throws -> String {
        let name = UUID().uuidString + "." + (["png", "jpg", "jpeg", "heic", "tiff", "gif", "pdf"].contains(ext.lowercased()) ? ext.lowercased() : "png")
        try write(data,url.appendingPathComponent("assets").appendingPathComponent(name))
        return name
    }

    /// Imports a related set as one operation. A later failure removes only files
    /// created by this call, leaving prior board assets untouched.
    public func importAssets(_ assets: [(data: Data, extension: String)], to url: URL) throws -> [String] {
        var created: [String] = []
        do {
            for asset in assets { created.append(try importAsset(data:asset.data,extension:asset.extension,to:url)) }
            return created
        } catch {
            discardAssets(created,at:url)
            throw error
        }
    }

    /// Removes exact, known orphan results. Unsafe names and symlinks are ignored.
    public func discardAssets(_ names: [String], at url: URL) {
        let folder = url.appendingPathComponent("assets",isDirectory:true)
        for name in Set(names) where Self.isSafeAssetName(name) {
            let file = folder.appendingPathComponent(name)
            guard let values = try? file.resourceValues(forKeys:[.isRegularFileKey,.isSymbolicLinkKey]),
                  values.isRegularFile == true, values.isSymbolicLink != true else { continue }
            try? fm.removeItem(at:file)
        }
    }

    /// Previews what explicit compaction would remove without changing files.
    public func unusedAssets(at url: URL, retaining undoAssets: Set<String> = []) throws -> [String] {
        let assetsFolder = url.appendingPathComponent("assets",isDirectory:true)
        let values = try assetsFolder.resourceValues(forKeys:[.isDirectoryKey,.isSymbolicLinkKey])
        guard values.isDirectory == true, values.isSymbolicLink != true,
              undoAssets.allSatisfy({Self.isSafeAssetName($0)}) else { throw BoardError.invalidData }
        var retained = undoAssets
        func retain(from file: URL) throws {
            guard fm.fileExists(atPath:file.path) else { return }
            let board = try JSONDecoder().decode(Board.self,from:readMetadata(file)).validated()
            retained.formUnion(board.images.flatMap {[$0.asset] + ($0.vectorAsset.map {[$0]} ?? [])})
        }
        try retain(from:url.appendingPathComponent("board.json"))
        try retain(from:url.appendingPathComponent("previous.json"))
        for snapshot in try history(url) { try retain(from:try historyFolder(url).appendingPathComponent(snapshot.filename)) }

        var unused: [String] = []
        for file in try fm.contentsOfDirectory(at:assetsFolder,includingPropertiesForKeys:[.isRegularFileKey,.isSymbolicLinkKey],options:[.skipsHiddenFiles]) {
            let name = file.lastPathComponent
            let item = try file.resourceValues(forKeys:[.isRegularFileKey,.isSymbolicLinkKey])
            guard item.isRegularFile == true, item.isSymbolicLink != true, Self.isSafeAssetName(name) else { continue }
            guard UUID(uuidString:file.deletingPathExtension().lastPathComponent) != nil,
                  ["png","jpg","jpeg","heic","tiff","gif","pdf"].contains(file.pathExtension.lowercased()) else { continue }
            if !retained.contains(name) { unused.append(name) }
        }
        return unused.sorted()
    }

    /// Explicit maintenance only. Retains every asset referenced by current,
    /// previous and recovery metadata, plus assets held by the caller's undo stack.
    @discardableResult public func compactAssets(at url: URL, retaining undoAssets: Set<String> = []) throws -> [String] {
        let unused = try unusedAssets(at:url,retaining:undoAssets)
        let folder = url.appendingPathComponent("assets",isDirectory:true)
        for name in unused { try fm.removeItem(at:folder.appendingPathComponent(name)) }
        return unused
    }

    private static func isSafeAssetName(_ name: String) -> Bool {
        !name.isEmpty && name == URL(fileURLWithPath:name).lastPathComponent && !name.contains("..")
    }
}

private struct Digest256: Equatable {
    private let bytes: [UInt8]
    init(_ data: Data) {
        bytes = Array(SHA256.hash(data:data))
    }
}
