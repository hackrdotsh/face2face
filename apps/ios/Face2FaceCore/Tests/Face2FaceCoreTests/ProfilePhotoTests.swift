import Foundation
import Testing

@testable import Face2FaceCore

private let avatarJSON = #"""
    {"avatar":{"seed":"mr9X39HdFM3-NfQ1kPuGVg",
    "photo":{"large":"/media/profiles/p/large?expires=1&signature=a","thumb":"/media/profiles/p/thumb?expires=1&signature=b"}}}
    """#

@Test func uploadsThePhotoAsMultipart() async throws {
    let transport = StubTransport([response(json: avatarJSON)])
    let client = APIClient(
        configuration: try configuration(), tokens: MemoryTokens("t"), transport: transport)
    let avatar = try await client.uploadProfilePhoto(jpeg: Data([0xFF, 0xD8, 0xFF]))
    #expect(avatar.photo?.thumb == "/media/profiles/p/thumb?expires=1&signature=b")
    let request = try #require(await transport.requests.first)
    #expect(request.httpMethod == "PUT")
    #expect(request.url?.path == "/api/profile/photo")
    let contentType = try #require(request.value(forHTTPHeaderField: "Content-Type"))
    #expect(contentType.hasPrefix("multipart/form-data; boundary="))
    let body = String(decoding: request.httpBody ?? Data(), as: UTF8.self)
    #expect(body.contains(#"name="image"; filename="photo.jpg""#))
    #expect(body.contains("Content-Type: image/jpeg"))
}

@Test func buildsAMultipartBodyAroundTheFile() {
    let form = MultipartForm(
        fileField: "image", fileName: "a.jpg", contentType: "image/jpeg", data: Data("JPEG".utf8),
        boundary: "B")
    #expect(form.contentType == "multipart/form-data; boundary=B")
    #expect(
        String(decoding: form.body, as: UTF8.self)
            == "--B\r\nContent-Disposition: form-data; name=\"image\"; filename=\"a.jpg\"\r\n"
            + "Content-Type: image/jpeg\r\n\r\nJPEG\r\n--B--\r\n")
}

@Test func removesThePhoto() async throws {
    let transport = StubTransport([
        response(json: #"{"avatar":{"seed":"AAAAAAAAAAAAAAAAAAAAAA","photo":null}}"#)
    ])
    let client = APIClient(
        configuration: try configuration(), tokens: MemoryTokens("t"), transport: transport)
    #expect(try await client.removeProfilePhoto().photo == nil)
    #expect(await transport.requests.first?.httpMethod == "DELETE")
}

@Test func keepsTheSignatureWhenResolvingAMediaPath() throws {
    let url = try configuration().mediaURL(for: "/media/profiles/p/thumb?expires=1&signature=a-b_c")
    #expect(
        url?.absoluteString == "https://api.example.test/media/profiles/p/thumb?expires=1&signature=a-b_c")
}

@Test func decodesAnImageFieldWithItsPhoto() throws {
    let json = #"""
        {"complete":true,"fields":[{"key":"photo","type":"image","label":"Profile photo","required":false,
        "value":{"large":"/l","thumb":"/t"}},
        {"key":"empty","type":"image","label":"Profile photo","required":false,"value":null}]}
        """#
    let state = try JSONDecoder().decode(OnboardingState.self, from: Data(json.utf8))
    #expect(state.fields[0].type == .image)
    #expect(state.fields[0].value == .photo(ProfilePhoto(large: "/l", thumb: "/t")))
    let form = OnboardingForm(state: state)
    #expect(form.fields.map(\.key) == ["empty"])
    #expect(form.values().isEmpty)
}
