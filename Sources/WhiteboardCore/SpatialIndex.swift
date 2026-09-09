import Foundation

/// A small deterministic grid index for canvas objects. Query results retain the
/// insertion order so indexing cannot change painting or keyboard navigation order.
public struct SpatialIndex {
    private let cellSize: Double
    private var cells: [Cell: [UUID]] = [:]
    private var overflow: [UUID] = []
    private var order: [UUID: Int] = [:]

    private struct Cell: Hashable { let x: Int; let y: Int }
    private func coordinate(_ value: Double) -> Int {
        let scaled = floor(value / cellSize)
        return Int(max(-1_000_000_000,min(1_000_000_000,scaled)))
    }

    public init(_ entries: [(UUID, Rect)], cellSize: Double = 512) {
        self.cellSize = max(64, cellSize)
        for (position, entry) in entries.enumerated() {
            let (id, rect) = entry
            order[id] = position
            let x0 = coordinate(rect.x), x1 = coordinate(rect.x + rect.width)
            let y0 = coordinate(rect.y), y1 = coordinate(rect.y + rect.height)
            let span = Double(max(1,x1-x0+1)) * Double(max(1,y1-y0+1))
            if span > 256 { overflow.append(id); continue }
            for x in x0...x1 { for y in y0...y1 { cells[Cell(x:x,y:y),default:[]].append(id) } }
        }
    }

    public func ids(intersecting rect: Rect) -> [UUID] {
        let x0 = coordinate(rect.x), x1 = coordinate(rect.x + rect.width)
        let y0 = coordinate(rect.y), y1 = coordinate(rect.y + rect.height)
        guard Double(max(1,x1-x0+1)) * Double(max(1,y1-y0+1)) <= 4096 else {
            return order.keys.sorted { order[$0]! < order[$1]! }
        }
        var result = Set(overflow)
        for x in x0...x1 { for y in y0...y1 { result.formUnion(cells[Cell(x:x,y:y)] ?? []) } }
        return result.sorted { order[$0]! < order[$1]! }
    }
}
