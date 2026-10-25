import Foundation

extension APIClient {
    /// Uploads a square JPEG as the profile photo. The server strips metadata and makes its own sizes.
    public func uploadProfilePhoto(jpeg: Data) async throws -> Avatar {
        let form = MultipartForm(
            fileField: "image", fileName: "photo.jpg", contentType: "image/jpeg", data: jpeg)
        let response = try await send(
            APIRequest(
                path: "api/profile/photo", method: "PUT", body: form.body, contentType: form.contentType,
                timeout: Self.uploadTimeout, authenticated: true))
        return try decode(AvatarResponse.self, from: response).avatar
    }

    public func removeProfilePhoto() async throws -> Avatar {
        let response = try await send(
            APIRequest(path: "api/profile/photo", method: "DELETE", authenticated: true))
        return try decode(AvatarResponse.self, from: response).avatar
    }

    private static let uploadTimeout: TimeInterval = 60
}

private struct AvatarResponse: Decodable {
    let avatar: Avatar
}

/// A `multipart/form-data` body with one file.
struct MultipartForm {
    let body: Data
    let contentType: String

    init(
        fileField: String, fileName: String, contentType fileType: String, data: Data,
        boundary: String = UUID().uuidString
    ) {
        var body = Data()
        body.append(Data("--\(boundary)\r\n".utf8))
        body.append(
            Data("Content-Disposition: form-data; name=\"\(fileField)\"; filename=\"\(fileName)\"\r\n".utf8))
        body.append(Data("Content-Type: \(fileType)\r\n\r\n".utf8))
        body.append(data)
        body.append(Data("\r\n--\(boundary)--\r\n".utf8))
        self.body = body
        contentType = "multipart/form-data; boundary=\(boundary)"
    }
}
