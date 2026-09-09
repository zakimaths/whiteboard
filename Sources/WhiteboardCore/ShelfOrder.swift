import Foundation

/// Small per-library preferences; listing the shelf never opens board contents or images.
public struct ShelfOrder: Codable, Equatable {
    public var pinned: Set<String> = []
    public var order: [String] = []
    public init() {}
    public static func key(_ item: ShelfItem) -> String { item.status.rawValue+"/"+item.url.lastPathComponent }
    public func sorted(_ items: [ShelfItem]) -> [ShelfItem] {
        var ranks: [String:Int] = [:]
        for (i,key) in order.enumerated() where ranks[key] == nil { ranks[key] = i }
        return items.sorted {
            let a = Self.key($0), b = Self.key($1)
            if pinned.contains(a) != pinned.contains(b) { return pinned.contains(a) }
            let ar = ranks[a] ?? Int.max, br = ranks[b] ?? Int.max
            if ar != br { return ar < br }
            return $0.title.localizedStandardCompare($1.title) == .orderedAscending
        }
    }
    public mutating func togglePin(_ item: ShelfItem) {
        let key = Self.key(item)
        if !pinned.insert(key).inserted { pinned.remove(key) }
    }
    @discardableResult public mutating func move(_ item: ShelfItem, by offset: Int, among items: [ShelfItem]) -> Bool {
        let key = Self.key(item)
        var group = sorted(items.filter { $0.status == item.status && pinned.contains(Self.key($0)) == pinned.contains(key) }).map(Self.key)
        guard offset == -1 || offset == 1, let index = group.firstIndex(of:key), group.indices.contains(index+offset) else { return false }
        group.swapAt(index,index+offset)
        let groupKeys = Set(group)
        order.removeAll {groupKeys.contains($0)}; order.append(contentsOf:group)
        return true
    }
    public mutating func relocate(from old: ShelfItem, to new: ShelfItem) {
        let a = Self.key(old), b = Self.key(new)
        guard a != b else { return }
        if pinned.remove(a) != nil { pinned.insert(b) }
        order = order.map {$0 == a ? b : $0}
    }
}
