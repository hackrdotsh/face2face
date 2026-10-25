import Foundation
import ImageIO
import UniformTypeIdentifiers

enum ChatPhoto {
    /// Bound decoded dimensions, honor orientation and omit source EXIF/GPS before upload.
    nonisolated static func jpeg(_ data: Data) throws -> Data {
        guard data.count <= 30 * 1024 * 1024,
            let source = CGImageSourceCreateWithData(data as CFData, nil),
            CGImageSourceGetType(source) != nil,
            let thumbnail = CGImageSourceCreateThumbnailAtIndex(
                source, 0,
                [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: 2048,
                    kCGImageSourceShouldCache: false,
                ] as CFDictionary)
        else { throw PhotoError.unreadable }
        let output = NSMutableData()
        guard
            let destination = CGImageDestinationCreateWithData(
                output, UTType.jpeg.identifier as CFString, 1, nil)
        else { throw PhotoError.unreadable }
        CGImageDestinationAddImage(
            destination, thumbnail, [kCGImageDestinationLossyCompressionQuality: 0.85] as CFDictionary)
        guard CGImageDestinationFinalize(destination), output.length <= 15 * 1024 * 1024 else {
            throw PhotoError.unreadable
        }
        return output as Data
    }
}
