import Foundation
import Testing

@testable import Face2FaceCore

private struct ExpectedAvatar: Decodable {
    let start: BlobAvatar.Point
    let curves: [BlobAvatar.Curve]
    let eyes: [BlobAvatar.Eye]
    let fill: [BlobAvatar.HSL]
    let eyeColor: BlobAvatar.HSL
}

private struct FixtureCase: Decodable, CustomTestStringConvertible {
    let seed: String
    let avatar: ExpectedAvatar
    var testDescription: String { seed }
}

/// Shared with the web client, so both draw the same blob for a seed.
private let fixtureCases: [FixtureCase] = {
    let url = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .appendingPathComponent("../../../../../docs/fixtures/blob-avatar.json")
        .standardized
    do {
        return try JSONDecoder().decode([FixtureCase].self, from: Data(contentsOf: url))
    } catch {
        fatalError("Cannot read \(url.path): \(error)")
    }
}()

private let tolerance = 1e-9

private func isClose(_ actual: BlobAvatar.Point, _ expected: BlobAvatar.Point) -> Bool {
    abs(actual.x - expected.x) < tolerance && abs(actual.y - expected.y) < tolerance
}

@Test(arguments: fixtureCases)
private func matchesTheSharedFixture(_ fixture: FixtureCase) throws {
    let avatar = try #require(BlobAvatar(seed: fixture.seed))
    let expected = fixture.avatar
    #expect(isClose(avatar.start, expected.start))
    #expect(avatar.curves.count == expected.curves.count)
    for (curve, expectedCurve) in zip(avatar.curves, expected.curves) {
        #expect(isClose(curve.control1, expectedCurve.control1))
        #expect(isClose(curve.control2, expectedCurve.control2))
        #expect(isClose(curve.end, expectedCurve.end))
    }
    #expect(avatar.eyes.count == 2)
    for (eye, expectedEye) in zip(avatar.eyes, expected.eyes) {
        #expect(
            isClose(
                BlobAvatar.Point(x: eye.x, y: eye.y), BlobAvatar.Point(x: expectedEye.x, y: expectedEye.y)))
        #expect(abs(eye.width - expectedEye.width) < tolerance)
        #expect(abs(eye.height - expectedEye.height) < tolerance)
    }
    #expect(avatar.fill == expected.fill)
    #expect(avatar.eyeColor == expected.eyeColor)
}

@Test func fixtureCoversEveryPointCount() {
    #expect(Set(fixtureCases.map(\.avatar.curves.count)) == [6, 7, 8])
}

@Test func rejectsASeedThatIsNotBase64URL() {
    #expect(BlobAvatar(seed: "not base64!") == nil)
}

@Test(arguments: [
    (BlobAvatar.HSL(hue: 0, saturation: 1, lightness: 0.5), (1.0, 0.0, 0.0)),
    (BlobAvatar.HSL(hue: 120, saturation: 1, lightness: 0.5), (0.0, 1.0, 0.0)),
    (BlobAvatar.HSL(hue: 240, saturation: 1, lightness: 0.25), (0.0, 0.0, 0.5)),
    (BlobAvatar.HSL(hue: 30, saturation: 0.8, lightness: 0.82), (0.964, 0.82, 0.676)),
])
func convertsHSLToRGB(_ color: BlobAvatar.HSL, _ expected: (Double, Double, Double)) {
    let rgb = color.rgb
    #expect(abs(rgb.red - expected.0) < 1e-3)
    #expect(abs(rgb.green - expected.1) < 1e-3)
    #expect(abs(rgb.blue - expected.2) < 1e-3)
}
