import Foundation

public struct RecognisedShape {
    public let name: String
    public let points: [Point]
}

/// Conservative, local geometry fitting. Called once at pen-up; ambiguous ink stays ink.
/// Work is capped at 20,000 input points, resampled to 128 before fitting.
public enum ShapeRecognition {
    public static func recognise(_ input: [Point], zoom: Double = 1, width: Double = 3) -> RecognisedShape? {
        guard input.count >= 3, input.count <= 20_000, zoom.isFinite, zoom > 0,
              input.allSatisfy({$0.x.isFinite && $0.y.isFinite}) else { return nil }
        let points = resample(input), first = points[0], last = points[points.count-1]
        let box = bounds(points), span = max(box.width,box.height), length = pathLength(points)
        guard span*zoom >= 28, length > 0 else { return nil }
        let chord = distance(first,last)
        if chord > span*0.8, length/chord < 1.08 {
            let errors = points.map {segmentDistance($0,first,last)/chord}
            if rms(errors) < 0.012, errors.max()! < 0.035 {
                return RecognisedShape(name:"Line",points:[first,last])
            }
        }
        if let arrow = arrow(points,span:span,width:width) ?? arrow(Array(points.reversed()),span:span,width:width) { return arrow }
        guard chord < span*0.2, min(box.width,box.height)*zoom >= 24 else { return nil }
        // Check closed boxes before ellipses; four-corner coverage rejects triangles and circles.
        if let rectangle = rectangle(points,span:span,length:length) { return rectangle }
        let cx = box.x+box.width/2, cy = box.y+box.height/2, rx = box.width/2, ry = box.height/2
        let radial = points.map {abs(hypot(($0.x-cx)/rx,($0.y-cy)/ry)-1)}
        guard rms(radial) < 0.065, radial.max()! < 0.18 else { return nil }
        let angles = points.map {atan2(($0.y-cy)/ry,($0.x-cx)/rx)}
        var turn = 0.0, travel = 0.0
        for i in 1..<angles.count {
            var delta = angles[i]-angles[i-1]
            if delta > .pi { delta -= 2 * .pi }; if delta < -.pi { delta += 2 * .pi }
            turn += delta; travel += abs(delta)
        }
        guard abs(turn) > 5.7, abs(turn) < 6.8, travel-abs(turn) < 0.5 else { return nil }
        let isCircle = min(rx,ry)/max(rx,ry) > 0.88
        let radius = (rx+ry)/2
        let start = isCircle ? Point(cx-radius,cy-radius) : Point(box.x,box.y)
        let end = isCircle ? Point(cx+radius,cy+radius) : Point(box.x+box.width,box.y+box.height)
        return RecognisedShape(name:isCircle ? "Circle" : "Ellipse",points:DrawingShape.ellipse.points(from:start,to:end))
    }
    private static func arrow(_ points: [Point], span: Double, width: Double) -> RecognisedShape? {
        let vertices = simplify(points,tolerance:span*0.025)
        guard vertices.count == 5 else { return nil }
        let start = vertices[0], tip = Point((vertices[1].x+vertices[3].x)/2,(vertices[1].y+vertices[3].y)/2)
        let length = distance(start,tip)
        guard length > span*0.7, distance(vertices[1],vertices[3]) < length*0.08 else { return nil }
        let ux = (tip.x-start.x)/length, uy = (tip.y-start.y)/length
        let wings = [vertices[2],vertices[4]]
        let along = wings.map {($0.x-tip.x)*ux+($0.y-tip.y)*uy}
        let across = wings.map {($0.x-tip.x)*uy-($0.y-tip.y)*ux}
        guard along.allSatisfy({$0 < -length*0.035 && $0 > -length*0.4}),
              across[0]*across[1] < 0, across.allSatisfy({abs($0) > length*0.025 && abs($0) < length*0.3}) else { return nil }
        let head = (-along[0]-along[1])/2, halfWidth = (abs(across[0])+abs(across[1]))/2
        guard max(abs(across[0]),abs(across[1])) < min(abs(across[0]),abs(across[1]))*2.2 else { return nil }
        let left = Point(tip.x-head*ux-halfWidth*uy,tip.y-head*uy+halfWidth*ux)
        let right = Point(tip.x-head*ux+halfWidth*uy,tip.y-head*uy-halfWidth*ux)
        // Preserve the drawn head size instead of imposing the explicit arrow tool's preset.
        return RecognisedShape(name:"Arrow",points:[start,tip,left,tip,right])
    }
    private static func rectangle(_ points: [Point], span: Double, length: Double) -> RecognisedShape? {
        var best: (Double,[Point])?
        for degrees in stride(from:0.0,to:90,by:3) {
            let angle = degrees * .pi/180, c = cos(angle), s = sin(angle)
            let rotated = points.map {Point($0.x*c+$0.y*s,-$0.x*s+$0.y*c)}, box = bounds(rotated)
            let perimeter = 2*(box.width+box.height)
            guard min(box.width,box.height) > span*0.18, length/perimeter > 0.82, length/perimeter < 1.15 else { continue }
            let corners = [Point(box.x,box.y),Point(box.x+box.width,box.y),Point(box.x+box.width,box.y+box.height),Point(box.x,box.y+box.height)]
            guard corners.allSatisfy({corner in rotated.map {distance($0,corner)}.min()! < min(box.width,box.height)*0.18}) else { continue }
            let errors = rotated.map {p in (0..<4).map {segmentDistance(p,corners[$0],corners[($0+1)%4])}.min()!/span}
            let score = rms(errors)
            guard score < 0.024, errors.max()! < 0.065 else { continue }
            if best == nil || score < best!.0 {
                let result = (corners+[corners[0]]).map {Point($0.x*c-$0.y*s,$0.x*s+$0.y*c)}
                best = (score,result)
            }
        }
        return best.map {RecognisedShape(name:"Rectangle",points:$0.1)}
    }
    private static func bounds(_ points: [Point]) -> Rect {
        let x = points.map(\.x), y = points.map(\.y)
        return Rect(x.min()!,y.min()!,x.max()!-x.min()!,y.max()!-y.min()!)
    }
    private static func distance(_ a: Point,_ b: Point) -> Double { hypot(a.x-b.x,a.y-b.y) }
    private static func pathLength(_ points: [Point]) -> Double { (1..<points.count).reduce(0) {$0+distance(points[$1-1],points[$1])} }
    private static func rms(_ values: [Double]) -> Double { sqrt(values.reduce(0) {$0+$1*$1}/Double(values.count)) }
    private static func segmentDistance(_ p: Point,_ a: Point,_ b: Point) -> Double {
        let dx = b.x-a.x, dy = b.y-a.y, size = dx*dx+dy*dy
        let t = size == 0 ? 0 : max(0,min(1,((p.x-a.x)*dx+(p.y-a.y)*dy)/size))
        return hypot(p.x-a.x-t*dx,p.y-a.y-t*dy)
    }
    private static func resample(_ input: [Point]) -> [Point] {
        let length = pathLength(input)
        guard length > 0 else { return [input[0],input[0]] }
        let step = length/127
        var result = [input[0]], traversed = 0.0, target = step
        for i in 1..<input.count {
            let a = input[i-1], b = input[i], segment = distance(a,b)
            while segment > 0, target <= traversed+segment, result.count < 127 {
                let t = (target-traversed)/segment
                result.append(Point(a.x+(b.x-a.x)*t,a.y+(b.y-a.y)*t)); target += step
            }
            traversed += segment
        }
        result.append(input[input.count-1]); return result
    }
    private static func simplify(_ points: [Point], tolerance: Double) -> [Point] {
        guard points.count > 2 else { return points }
        var largest = 0.0, index = 0
        for i in 1..<(points.count-1) {
            let d = segmentDistance(points[i],points[0],points[points.count-1])
            if d > largest { largest = d; index = i }
        }
        if largest <= tolerance { return [points[0],points[points.count-1]] }
        return Array(simplify(Array(points[...index]),tolerance:tolerance).dropLast()) + simplify(Array(points[index...]),tolerance:tolerance)
    }
}
