import Foundation

#if canImport(CoreGraphics)
    import CoreGraphics
#endif

/// A square viewport over an image that fills it at zoom 1. The person pans and zooms the image,
/// and the circle inscribed in the viewport is the photo they keep.
public struct PhotoCrop: Equatable, Sendable {
    public static let maxZoom: CGFloat = 4
    /// The server makes its own sizes, so a larger upload adds nothing.
    public static let maxOutputEdge: CGFloat = 2048

    public let imageSize: CGSize
    public let viewportSide: CGFloat
    public private(set) var zoom: CGFloat = 1
    /// How far the image's center sits from the viewport's center, in viewport points.
    public private(set) var offset: CGSize = .zero

    public init(imageSize: CGSize, viewportSide: CGFloat) {
        self.imageSize = imageSize
        self.viewportSide = viewportSide
    }

    /// Viewport points for each image point.
    public var scale: CGFloat {
        viewportSide / min(imageSize.width, imageSize.height) * zoom
    }

    /// The image's size on screen.
    public var displayedSize: CGSize {
        CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
    }

    /// Keeps the zoom in range and the image covering the viewport.
    public mutating func move(zoom newZoom: CGFloat, offset newOffset: CGSize) {
        zoom = min(max(newZoom, 1), Self.maxZoom)
        let slack = CGSize(
            width: (displayedSize.width - viewportSide) / 2, height: (displayedSize.height - viewportSide) / 2
        )
        offset = CGSize(
            width: min(max(newOffset.width, -slack.width), slack.width),
            height: min(max(newOffset.height, -slack.height), slack.height))
    }

    /// The square of the image under the viewport, in image points.
    public var sourceRect: CGRect {
        let side = viewportSide / scale
        let centerX = imageSize.width / 2 - offset.width / scale
        let centerY = imageSize.height / 2 - offset.height / scale
        return CGRect(x: centerX - side / 2, y: centerY - side / 2, width: side, height: side)
    }

    /// The output side in pixels for an image with `pixelsPerPoint`, capped at `maxOutputEdge`.
    public func outputSide(pixelsPerPoint: CGFloat) -> CGFloat {
        min((sourceRect.width * pixelsPerPoint).rounded(.down), Self.maxOutputEdge)
    }
}
