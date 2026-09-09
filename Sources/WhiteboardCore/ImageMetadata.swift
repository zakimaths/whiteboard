import Foundation
import ImageIO

public struct ImageMetadata: Equatable {
    public let width: Double
    public let height: Double
    public let orientation: Int

    public static func inspect(
        _ data: Data,
        byteLimit: Int = 32 * 1024 * 1024,
        pixelLimit: Double = 100_000_000
    ) throws -> ImageMetadata {
        guard data.count <= byteLimit,
              let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let rawWidth = properties[kCGImagePropertyPixelWidth] as? Double,
              let rawHeight = properties[kCGImagePropertyPixelHeight] as? Double,
              rawWidth.isFinite, rawHeight.isFinite, rawWidth > 0, rawHeight > 0,
              rawWidth * rawHeight <= pixelLimit else { throw BoardError.invalidData }

        let orientation = (properties[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? 1
        let swapsAxes = (5...8).contains(orientation)
        return ImageMetadata(
            width: swapsAxes ? rawHeight : rawWidth,
            height: swapsAxes ? rawWidth : rawHeight,
            orientation: orientation
        )
    }

    public static func inspect(
        file url: URL,
        byteLimit: Int = 32 * 1024 * 1024,
        pixelLimit: Double = 100_000_000
    ) throws -> (metadata: ImageMetadata, data: Data) {
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true,
              let size = values.fileSize, size <= byteLimit else { throw BoardError.invalidData }
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        return (try inspect(data, byteLimit: byteLimit, pixelLimit: pixelLimit), data)
    }
}
