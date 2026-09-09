import Foundation
import CoreGraphics
import ImageIO
import WhiteboardCore

/// Called from main.swift by the audit integration commit.
func runAuditStorageChecks() {
    check("Content digest detects an external edit with a preserved modification date") {
        try temporaryLibrary { library in
            let url = try library.create(), file = url.appendingPathComponent("board.json")
            let original = try library.load(url)
            let date = try FileManager.default.attributesOfItem(atPath:file.path)[.modificationDate] as! Date
            var external = original; external.recognisedText = "same timestamp, different content"
            try JSONEncoder().encode(external).write(to:file,options:.atomic)
            try FileManager.default.setAttributes([.modificationDate:date],ofItemAtPath:file.path)
            try rejects { try library.save(original,at:url) }
            try expect(try JSONDecoder().decode(Board.self,from:Data(contentsOf:file)).recognisedText == external.recognisedText)
        }
    }

    check("Batch asset import removes only this operation's partial files") {
        try temporaryLibrary { initial in
            let package = try initial.create()
            let prior = try initial.importAsset(data:Data([9]),extension:"png",to:package)
            var writes = 0
            let library = try Library(root:initial.root,atomicWrite:{data,url in
                if url.deletingLastPathComponent().lastPathComponent == "assets" {
                    writes += 1; if writes == 2 { throw NSError(domain:NSCocoaErrorDomain,code:NSFileWriteOutOfSpaceError) }
                }
                try data.write(to:url,options:.atomic)
            })
            try rejects { _ = try library.importAssets([(Data([1]),"png"),(Data([2]),"pdf")],to:package) }
            let files = try FileManager.default.contentsOfDirectory(atPath:package.appendingPathComponent("assets").path)
            try expect(files == [prior])
        }
    }

    check("Tray scan isolates corrupt items and removal can be undone") {
        try temporaryLibrary { library in
            let tray = CaptureTray(libraryRoot:library.root), png = try trayPNG()
            let healthy = try tray.add(png,extension:"png",title:"Healthy")
            let damagedID = UUID(), damaged = tray.root.appendingPathComponent(damagedID.uuidString,isDirectory:true)
            try FileManager.default.createDirectory(at:damaged,withIntermediateDirectories:false)
            try Data("broken".utf8).write(to:damaged.appendingPathComponent("reference.json"))
            let scan = try tray.scan()
            try expect(scan.references == [healthy] && scan.diagnostics.count == 1 && scan.diagnostics[0].referenceID == damagedID)
            let removal = try tray.remove(healthy.id)
            try expect(try tray.references().isEmpty)
            try tray.restore(removal)
            try expect(try tray.data(for:healthy.id).1 == png)
            let damagedRemoval = try tray.removeDamaged(damagedID)
            try expect(try tray.scan().diagnostics.isEmpty)
            try tray.restore(damagedRemoval)
            try expect(try tray.scan().diagnostics.count == 1)
        }
    }

    check("Image metadata observes orientation and rejects oversized input before decoding") {
        let bitmap = CGContext(data:nil,width:40,height:20,bitsPerComponent:8,bytesPerRow:160,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
        let data = NSMutableData(), destination = CGImageDestinationCreateWithData(data,"public.jpeg" as CFString,1,nil)!
        CGImageDestinationAddImage(destination,bitmap.makeImage()!,[kCGImagePropertyOrientation:6] as CFDictionary)
        try expect(CGImageDestinationFinalize(destination))
        let metadata = try ImageMetadata.inspect(data as Data)
        try expect(metadata.width == 20 && metadata.height == 40 && metadata.orientation == 6)
        try rejects { _ = try ImageMetadata.inspect(Data(repeating:0,count:5),byteLimit:4) }
    }

    check("Explicit compaction retains recovery and caller-supplied undo assets") {
        try temporaryLibrary { library in
            let package = try library.create()
            let previousAsset = try library.importAsset(data:Data([1]),extension:"png",to:package)
            var previous = Board(); previous.images = [BoardImage(asset:previousAsset,frame:Rect(0,0,10,10))]
            try library.save(previous,at:package)
            let currentAsset = try library.importAsset(data:Data([2]),extension:"png",to:package)
            var current = Board(); current.images = [BoardImage(asset:currentAsset,frame:Rect(0,0,10,10))]
            try library.save(current,at:package)
            let undoAsset = try library.importAsset(data:Data([3]),extension:"pdf",to:package)
            let orphan = try library.importAsset(data:Data([4]),extension:"png",to:package)
            let removed = try library.compactAssets(at:package,retaining:[undoAsset])
            try expect(removed == [orphan])
            for name in [previousAsset,currentAsset,undoAsset] {
                try expect(FileManager.default.fileExists(atPath:package.appendingPathComponent("assets").appendingPathComponent(name).path))
            }
        }
    }
}
