import Foundation
import Testing

@testable import Face2FaceCore

@Test func startsWithTheCenteredSquareOfALandscapePhoto() {
    let crop = PhotoCrop(imageSize: CGSize(width: 3000, height: 1500), viewportSide: 300)
    #expect(crop.scale == 0.2)
    #expect(crop.sourceRect == CGRect(x: 750, y: 0, width: 1500, height: 1500))
}

@Test func keepsTheImageCoveringTheViewport() {
    var crop = PhotoCrop(imageSize: CGSize(width: 3000, height: 1500), viewportSide: 300)
    crop.move(zoom: 1, offset: CGSize(width: 1000, height: 50))
    #expect(crop.offset == CGSize(width: 150, height: 0))
    #expect(crop.sourceRect == CGRect(x: 0, y: 0, width: 1500, height: 1500))
}

@Test func zoomsIntoTheChosenSpot() {
    var crop = PhotoCrop(imageSize: CGSize(width: 1000, height: 1000), viewportSide: 250)
    crop.move(zoom: 2, offset: CGSize(width: -100, height: 100))
    #expect(crop.sourceRect == CGRect(x: 450, y: 50, width: 500, height: 500))
}

@Test func limitsZoomAndOutputSize() {
    var crop = PhotoCrop(imageSize: CGSize(width: 4000, height: 6000), viewportSide: 300)
    crop.move(zoom: 10, offset: .zero)
    #expect(crop.zoom == PhotoCrop.maxZoom)
    crop.move(zoom: 0.5, offset: .zero)
    #expect(crop.zoom == 1)
    #expect(crop.outputSide(pixelsPerPoint: 1) == PhotoCrop.maxOutputEdge)
    #expect(crop.outputSide(pixelsPerPoint: 0.25) == 1000)
}
