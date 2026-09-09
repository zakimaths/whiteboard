import Foundation

/// Shapes become ordinary editable ink, so old boards and exports need no new format.
public enum DrawingShape: String, CaseIterable {
    case line = "Line", arrow = "Arrow", rectangle = "Rectangle", ellipse = "Ellipse"

    public func points(from start: Point, to end: Point, constrained: Bool = false, width: Double = 3) -> [Point] {
        var dx = end.x-start.x, dy = end.y-start.y
        if constrained {
            if self == .line || self == .arrow {
                let length = hypot(dx,dy), angle = (atan2(dy,dx)/(.pi/4)).rounded() * (.pi/4)
                dx = cos(angle)*length; dy = sin(angle)*length
            } else {
                let side = max(abs(dx),abs(dy))
                dx = dx < 0 ? -side : side; dy = dy < 0 ? -side : side
            }
        }
        let tip = Point(start.x+dx,start.y+dy)
        switch self {
        case .line: return [start,tip]
        case .arrow:
            let length = hypot(dx,dy)
            guard length > 0.001 else { return [start] }
            let head = min(length*0.35,max(12,width*4)), ux = dx/length, uy = dy/length
            let left = Point(tip.x-head*ux-head*0.5*uy,tip.y-head*uy+head*0.5*ux)
            let right = Point(tip.x-head*ux+head*0.5*uy,tip.y-head*uy-head*0.5*ux)
            return [start,tip,left,tip,right]
        case .rectangle:
            return [start,Point(tip.x,start.y),tip,Point(start.x,tip.y),start]
        case .ellipse:
            let cx = start.x+dx/2, cy = start.y+dy/2
            var result = (0..<128).map { index -> Point in
                let angle = Double(index) * 2 * .pi/128
                return Point(cx+dx/2*cos(angle),cy+dy/2*sin(angle))
            }
            result.append(result[0]); return result
        }
    }
}
