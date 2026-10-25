import Face2FaceCore
import ImageIO
import XCTest

@testable import Face2Face

@MainActor
final class ChatModelTests: XCTestCase {
    func testPhotoPreviewAcknowledgesAndKeepsItsThumbnail() async {
        let session = SessionModel()
        session.enterTownPreview()
        let model = ChatConversationModel(chatID: "preview-ava", session: session)
        await model.run()
        XCTAssertTrue(model.send(photo: Data([1, 2, 3])))
        for _ in 0..<100 {
            if model.transcript.pending.isEmpty { break }
            await Task.yield()
        }
        XCTAssertTrue(model.transcript.pending.isEmpty)
        let message = model.transcript.messages.last
        XCTAssertNotNil(message.flatMap { model.localPreviewPhoto($0.id) })
        await model.stop()
    }
    func testPreviewSendConfirmsAndDoesNotDuplicateMessagesAfterResume() async {
        let session = SessionModel()
        session.enterTownPreview()
        let model = ChatConversationModel(chatID: "preview-ava", session: session)
        await model.run()
        XCTAssertEqual(model.state, .live)
        model.draft = "A real little hello"
        XCTAssertTrue(model.send(photo: nil))
        for _ in 0..<100 {
            if model.transcript.pending.isEmpty { break }
            await Task.yield()
        }
        XCTAssertEqual(model.transcript.messages.filter { $0.text == "A real little hello" }.count, 1)
        XCTAssertTrue(model.transcript.pending.isEmpty)
        await model.stop()
        await model.run()
        XCTAssertEqual(model.transcript.messages.filter { $0.text == "A real little hello" }.count, 1)
        await model.stop()
    }
    func testComposerRejectsWhitespaceAndMatchesServerUTF16Limit() async {
        let session = SessionModel()
        session.enterTownPreview()
        let model = ChatConversationModel(chatID: "preview-private", session: session)
        await model.run()
        XCTAssertEqual(model.summary?.title, "Anonymous connection")
        model.draft = "  \n "
        XCTAssertFalse(model.send(photo: nil))
        model.draft = String(repeating: "😀", count: 2001)
        XCTAssertFalse(model.send(photo: nil))
        await model.stop()
        model.draft = "Not while backgrounded"
        XCTAssertFalse(model.send(photo: nil))
    }
    func testPhotoPreparationBoundsPixelsAndRemovesGPSAndEXIF() throws {
        let apps = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let text = try String(contentsOf: apps.appendingPathComponent("api/test/fixtures/photo-with-exif.ts"), encoding: .utf8)
        let range = try XCTUnwrap(text.range(of: #"atob\(\s*"([^"]+)""#, options: .regularExpression))
        let original = try XCTUnwrap(Data(base64Encoded: String(text[range].split(separator: "\"")[1])))
        let prepared = try ChatPhoto.jpeg(original)
        let source = try XCTUnwrap(CGImageSourceCreateWithData(prepared as CFData, nil))
        let properties = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any])
        XCTAssertLessThanOrEqual(try XCTUnwrap(properties[kCGImagePropertyPixelWidth as String] as? Int), 2048)
        XCTAssertNil(properties[kCGImagePropertyGPSDictionary as String])
        // The JPEG encoder may synthesize dimensions/color space. No source metadata survives.
        let exif = properties[kCGImagePropertyExifDictionary as String] as? [String: Any] ?? [:]
        XCTAssertTrue(Set(exif.keys).isSubset(of: ["ColorSpace", "PixelXDimension", "PixelYDimension"]))
        XCTAssertNil(properties[kCGImagePropertyTIFFDictionary as String])
        XCTAssertNil(prepared.range(of: Data("f2f-exif-marker".utf8)))
        XCTAssertThrowsError(try ChatPhoto.jpeg(Data("not an image".utf8)))
    }
}
