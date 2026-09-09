import Foundation

public enum PreviewBudget {
    public static let bytes = 48 * 1024 * 1024
    public static let maximumVisibleImages = 128
    public static func maxPixelSize(visibleCount: Int) -> Int {
        // Allow up to 16 decoded bytes per pixel, including higher-depth inputs.
        let count = max(1, min(maximumVisibleImages, visibleCount))
        return min(1536, Int(sqrt(Double(bytes) / Double(count * 16))))
    }
}
