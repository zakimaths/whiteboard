import Foundation

public enum IdeaStatus: String, CaseIterable { case unfinished = "Unfinished", finished = "Finished", archived = "Archive" }

public struct ShelfItem: Equatable {
    public var url: URL
    public var status: IdeaStatus
    public var modified: Date
    public var title: String { url.deletingPathExtension().lastPathComponent }
}

// All operations are run on the application's single storage queue.
public final class Library {
    public let root: URL
    private let fm = FileManager.default
    private var knownVersions: [URL: Date] = [:]
    public init(root: URL) throws {
        self.root = root.standardizedFileURL
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
        return result
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
                result.append(ShelfItem(url: url, status: status, modified: values.contentModificationDate ?? .distantPast))
            }
        }
        return result.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }
    private func stamp(_ url: URL) throws -> Date {
        guard fm.fileExists(atPath: url.path) else { throw BoardError.missingFile }
        // URL resource values can cache a pre-replacement modification date.
        // Read fresh file attributes after every atomic replacement.
        return try fm.attributesOfItem(atPath: url.path)[.modificationDate] as? Date ?? .distantPast
    }
    public func load(_ url: URL) throws -> Board {
        let file = url.appendingPathComponent("board.json")
        let size = try file.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size < 64 * 1024 * 1024 else { throw BoardError.invalidData }
        let result = try JSONDecoder().decode(Board.self, from: Data(contentsOf: file)).validated()
        knownVersions[url] = try stamp(file)
        return result
    }
    public func save(_ board: Board, at url: URL, checkingVersion: Bool = true) throws {
        _ = try board.validated()
        let file = url.appendingPathComponent("board.json")
        guard fm.fileExists(atPath: url.path) else { throw BoardError.missingFile }
        if checkingVersion, let known = knownVersions[url], try stamp(file) != known { throw BoardError.conflict }
        let data = try JSONEncoder().encode(board)
        // Keep one recoverable previous version. Never move away the current valid file.
        if fm.fileExists(atPath: file.path) {
            let previous = try Data(contentsOf: file)
            try previous.write(to: url.appendingPathComponent("previous.json"), options: .atomic)
        }
        try data.write(to: file, options: .atomic)
        knownVersions[url] = try stamp(file)
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
        let candidate = folder(status).appendingPathComponent(Self.safeName(title)).appendingPathExtension("whiteboard")
        if candidate == url { return url }
        let destination = availableURL(name: title, status: status)
        try fm.moveItem(at: url, to: destination)
        knownVersions[destination] = knownVersions.removeValue(forKey: url)
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
        try data.write(to: url.appendingPathComponent("assets").appendingPathComponent(name), options: .atomic)
        return name
    }
}
