import Foundation
import CoreGraphics
import ImageIO

let folder = URL(fileURLWithPath:CommandLine.arguments[1],isDirectory:true)
try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
for size in [16,32,64,128,256,512,1024] {
    let context = CGContext(data:nil,width:size,height:size,bitsPerComponent:8,bytesPerRow:size*4,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.scaleBy(x:Double(size)/1024,y:Double(size)/1024)
    context.setFillColor(CGColor(red:0.97,green:0.96,blue:0.93,alpha:1))
    context.addPath(CGPath(roundedRect:CGRect(x:45,y:45,width:934,height:934),cornerWidth:205,cornerHeight:205,transform:nil)); context.fillPath()
    context.setFillColor(CGColor(red:0.17,green:0.2,blue:0.2,alpha:0.08))
    context.addPath(CGPath(roundedRect:CGRect(x:185,y:733,width:654,height:88),cornerWidth:32,cornerHeight:32,transform:nil)); context.fillPath()
    for (x,colour) in [(226.0,CGColor(red:0.90,green:0.30,blue:0.27,alpha:1)),(290.0,CGColor(red:0.2,green:0.62,blue:0.40,alpha:1))] {
        context.setFillColor(colour); context.fillEllipse(in:CGRect(x:x,y:757,width:40,height:40))
    }
    context.setLineCap(.round); context.setLineJoin(.round); context.setLineWidth(46)
    context.setStrokeColor(CGColor(red:0.15,green:0.32,blue:0.69,alpha:1))
    context.move(to:CGPoint(x:225,y:365))
    context.addCurve(to:CGPoint(x:490,y:440),control1:CGPoint(x:320,y:735),control2:CGPoint(x:420,y:675))
    context.addCurve(to:CGPoint(x:635,y:380),control1:CGPoint(x:550,y:240),control2:CGPoint(x:552,y:290))
    context.addLine(to:CGPoint(x:792,y:570)); context.strokePath()
    let image = context.makeImage()!
    let filenames: [String]
    switch size { case 16: filenames=["icon_16x16"]; case 32: filenames=["icon_16x16@2x","icon_32x32"]; case 64: filenames=["icon_32x32@2x"]; case 128: filenames=["icon_128x128"]; case 256: filenames=["icon_128x128@2x","icon_256x256"]; case 512: filenames=["icon_256x256@2x","icon_512x512"]; default: filenames=["icon_512x512@2x"] }
    for name in filenames {
        let url = folder.appendingPathComponent(name+".png")
        let destination = CGImageDestinationCreateWithURL(url as CFURL,"public.png" as CFString,1,nil)!
        CGImageDestinationAddImage(destination,image,nil); CGImageDestinationFinalize(destination)
    }
}
