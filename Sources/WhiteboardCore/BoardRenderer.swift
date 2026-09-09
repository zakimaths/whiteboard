import Foundation
import CoreGraphics
import CoreText
import ImageIO
import UniformTypeIdentifiers

/// An export uses an immutable document snapshot and decodes one source image at a time.
/// It never captures the desktop, controls, selection handles or preview placeholders.
public enum BoardRenderer {
    public static func textBounds(_ text: BoardText) -> Rect {
        let font = CTFontCreateWithName("Helvetica" as CFString, text.size, nil)
        let attributes = [kCTFontAttributeName:font] as CFDictionary
        let string = CFAttributedStringCreate(nil,text.text as CFString,attributes)!
        let setter = CTFramesetterCreateWithAttributedString(string)
        let size = CTFramesetterSuggestFrameSizeWithConstraints(setter,CFRange(location:0,length:0),nil,CGSize(width:100_000,height:100_000),nil)
        return Rect(text.origin.x,text.origin.y,max(1,ceil(size.width)+8),max(text.size*1.5,ceil(size.height)+8))
    }
    public static func contentBounds(_ board: Board, padding: Double = 32) -> Rect {
        let boxes = board.ink.map(\.bounds)+board.images.map(\.frame)+board.texts.map {textBounds($0)}
        guard let first = boxes.first else { return Rect(0,0,800,500) }
        let x = boxes.reduce(first.x) {min($0,$1.x)}, y = boxes.reduce(first.y) {min($0,$1.y)}
        let right = boxes.reduce(first.x+first.width) {max($0,$1.x+$1.width)}
        let bottom = boxes.reduce(first.y+first.height) {max($0,$1.y+$1.height)}
        return Rect(x-padding,y-padding,right-x+2*padding,bottom-y+2*padding)
    }
    public static func png(_ board: Board, package: URL, region: Rect? = nil) throws -> Data {
        _ = try board.validated()
        let region = region ?? contentBounds(board)
        guard region.width.isFinite, region.height.isFinite, region.width > 0, region.height > 0 else { throw BoardError.invalidData }
        let scale = min(2,8192/max(region.width,region.height),sqrt(16_000_000/(region.width*region.height)))
        let width = max(1,Int(ceil(region.width*scale))), height = max(1,Int(ceil(region.height*scale)))
        guard let context = CGContext(data:nil,width:width,height:height,bitsPerComponent:8,bytesPerRow:width*4,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue) else { throw BoardError.invalidData }
        context.translateBy(x:0,y:CGFloat(height)); context.scaleBy(x:scale,y:-scale)
        context.translateBy(x:-region.x,y:-region.y)
        try draw(board, package:package, context:context, region:region, imageScale:scale)
        guard let image = context.makeImage() else { throw BoardError.invalidData }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data,UTType.png.identifier as CFString,1,nil) else { throw BoardError.invalidData }
        CGImageDestinationAddImage(destination,image,nil)
        guard CGImageDestinationFinalize(destination) else { throw BoardError.invalidData }
        return data as Data
    }
    public static func pdf(_ board: Board, package: URL, region: Rect? = nil) throws -> Data {
        _ = try board.validated()
        let region = region ?? contentBounds(board), scale = min(1,14_400/max(region.width,region.height))
        var media = CGRect(x:0,y:0,width:region.width*scale,height:region.height*scale)
        let data = NSMutableData()
        guard let consumer = CGDataConsumer(data:data), let context = CGContext(consumer:consumer,mediaBox:&media,nil) else { throw BoardError.invalidData }
        context.beginPDFPage(nil); context.translateBy(x:0,y:media.height); context.scaleBy(x:scale,y:-scale); context.translateBy(x:-region.x,y:-region.y)
        try draw(board,package:package,context:context,region:region,imageScale:min(2,scale*2))
        context.endPDFPage(); context.closePDF(); return data as Data
    }
    private static func color(_ name: String, alpha: Double = 1) -> CGColor {
        let rgb: [Double]
        switch name { case "blue": rgb = [0.0,0.42,0.92]; case "red": rgb = [0.88,0.19,0.20]; case "green": rgb = [0.13,0.59,0.32]; default: rgb = [0.16,0.19,0.19] }
        return CGColor(red:rgb[0],green:rgb[1],blue:rgb[2],alpha:alpha)
    }
    private static func draw(_ board: Board, package: URL, context: CGContext, region: Rect, imageScale: Double) throws {
        context.setFillColor(CGColor(red:0.975,green:0.969,blue:0.947,alpha:1))
        context.fill(CGRect(x:region.x,y:region.y,width:region.width,height:region.height))
        for item in board.images where item.frame.intersects(region) {
            if let asset = item.vectorAsset {
                let url = package.appendingPathComponent("assets").appendingPathComponent(asset)
                guard let document = CGPDFDocument(url as CFURL), let page = document.page(at:1) else { throw BoardError.missingFile }
                let box = page.getBoxRect(.mediaBox)
                guard box.width > 0, box.height > 0 else { throw BoardError.invalidData }
                context.saveGState(); context.translateBy(x:item.frame.x,y:item.frame.y+item.frame.height)
                context.scaleBy(x:item.frame.width/box.width,y:-item.frame.height/box.height)
                context.translateBy(x:-box.minX,y:-box.minY); context.drawPDFPage(page); context.restoreGState()
                continue
            }
            try autoreleasepool {
                let url = package.appendingPathComponent("assets").appendingPathComponent(item.asset)
                guard let source = CGImageSourceCreateWithURL(url as CFURL,[kCGImageSourceShouldCache:false] as CFDictionary),
                      let image = CGImageSourceCreateThumbnailAtIndex(source,0,[kCGImageSourceCreateThumbnailFromImageAlways:true,kCGImageSourceThumbnailMaxPixelSize:Int(min(4096,max(1,ceil(max(item.frame.width,item.frame.height)*imageScale)))),kCGImageSourceCreateThumbnailWithTransform:true,kCGImageSourceShouldCacheImmediately:true] as CFDictionary) else { throw BoardError.missingFile }
                context.saveGState(); context.translateBy(x:item.frame.x,y:item.frame.y+item.frame.height); context.scaleBy(x:1,y:-1)
                context.interpolationQuality = .high
                context.draw(image,in:CGRect(x:0,y:0,width:item.frame.width,height:item.frame.height)); context.restoreGState()
            }
        }
        context.setLineCap(.round); context.setLineJoin(.round)
        for ink in board.ink where ink.bounds.intersects(region) {
            guard let first = ink.points.first else { continue }
            context.setStrokeColor(color(ink.colour,alpha:ink.highlighter ? 0.28 : 1)); context.setLineWidth(ink.width)
            context.beginPath(); context.move(to:CGPoint(x:first.x,y:first.y))
            if ink.points.count == 1 { context.addLine(to:CGPoint(x:first.x+0.01,y:first.y)) }
            else { for point in ink.points.dropFirst() { context.addLine(to:CGPoint(x:point.x,y:point.y)) } }
            context.strokePath()
        }
        for text in board.texts {
            let rect = textBounds(text); guard rect.intersects(region) else { continue }
            let font = CTFontCreateWithName("Helvetica" as CFString,text.size,nil)
            let attrs = [kCTFontAttributeName:font,kCTForegroundColorAttributeName:color("ink")] as CFDictionary
            let string = CFAttributedStringCreate(nil,text.text as CFString,attrs)!
            let setter = CTFramesetterCreateWithAttributedString(string)
            let path = CGPath(rect:CGRect(x:0,y:0,width:rect.width,height:rect.height),transform:nil)
            context.saveGState(); context.translateBy(x:rect.x,y:rect.y+rect.height); context.scaleBy(x:1,y:-1); context.textMatrix = .identity
            CTFrameDraw(CTFramesetterCreateFrame(setter,CFRange(location:0,length:0),path,nil),context); context.restoreGState()
        }
    }
}
