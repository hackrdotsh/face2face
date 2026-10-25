import Foundation
import Testing

@testable import Face2FaceCore

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

private struct LiveChatTimeout: Error {}

/// Run only through scripts/chat-smoke.mjs: it provides an isolated local Worker and database.
@Test(.enabled(if: ProcessInfo.processInfo.environment["F2F_CHAT_SMOKE_URL"] != nil), .timeLimit(.minutes(1)))
func liveChatRoundTrip() async throws {
    let base = try #require(ProcessInfo.processInfo.environment["F2F_CHAT_SMOKE_URL"])
    let config = try APIConfiguration(address: base, allowInsecureHTTP: true)
    let firstTokens = MemoryTokens()
    let secondTokens = MemoryTokens()
    let first = APIClient(configuration: config, tokens: firstTokens)
    let second = APIClient(configuration: config, tokens: secondTokens)
    _ = try await livePost(config, path: "api/dev/seed", body: [:])
    try await first.signIn(email: "ava@seed.face2face.test", password: "face2face-seed-password")
    try await second.signIn(email: "ben@seed.face2face.test", password: "face2face-seed-password")
    let encounter = try await livePost(
        config, path: "api/dev/encounters", body: ["firstUserId": "seed-ava", "secondUserId": "seed-ben"])
    let object = try #require(JSONSerialization.jsonObject(with: encounter) as? [String: Any])
    let row = try #require(object["connection"] as? [String: Any])
    let id = try #require(row["id"] as? String)
    let firstAnswer = try await first.decideConnection(id, decision: .accepted)
    #expect(firstAnswer.isPending && firstAnswer.you?.decision == .accepted)
    let secondAnswer = try await second.decideConnection(id, decision: .accepted)
    #expect(secondAnswer.status == "private" && secondAnswer.them == nil)
    #expect(try await first.chat(id).title == "Anonymous connection")
    let a = URLSessionChatSocket()
    let b = URLSessionChatSocket()
    try await a.connect(to: first.chatSocketURL(id))
    try await b.connect(to: second.chatSocketURL(id))
    _ = try await liveFrame(a, type: "ready")
    _ = try await liveFrame(b, type: "ready")
    try await a.send(.typing(true))
    _ = try await liveFrame(b, type: "typing")
    let clientID = UUID().uuidString
    try await a.send(.send(clientId: clientID, text: "A real hello", imageId: nil))
    _ = try await liveFrame(a, type: "ack")
    let received = try await liveFrame(b, type: "message")
    if case .message(let message) = received {
        #expect(message.text == "A real hello" && message.from == .them && message.clientId == nil)
    }
    try await a.send(.send(clientId: clientID, text: "A real hello", imageId: nil))
    _ = try await liveFrame(a, type: "ack")
    #expect(try await first.chatMessages(id).messages.count == 1)
    // The same EXIF/GPS fixture used by the server tests, without copying the binary.
    let apps = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let source = try String(
        contentsOf: apps.appendingPathComponent("api/test/fixtures/photo-with-exif.ts"), encoding: .utf8)
    let range = try #require(source.range(of: #"atob\(\s*"([^"]+)""#, options: .regularExpression))
    let image = try #require(Data(base64Encoded: String(source[range].split(separator: "\"")[1])))
    for (sender, receiver, socket, peer) in [(first, second, a, b), (second, first, b, a)] {
        let uploaded = try await sender.uploadChatPhoto(id, jpeg: image)
        #expect(uploaded.variants.original.width <= 2048)
        try await socket.send(.send(clientId: UUID().uuidString, text: "A photo", imageId: uploaded.id))
        _ = try await liveFrame(socket, type: "ack")
        let frame = try await liveFrame(peer, type: "message")
        guard case .message(let message) = frame, let photo = message.image else {
            Issue.record("Missing photo delivery")
            return
        }
        #expect(message.from == .them)
        let url = try #require(config.mediaURL(for: photo.variants.thumb.path))
        let media = try await URLSessionTransport().send(URLRequest(url: url))
        #expect(media.status == 200 && !media.data.isEmpty)
        #expect(media.data.range(of: Data("f2f-exif-marker".utf8)) == nil)
        try await peer.send(.read(message.id))
        for _ in 0..<20 {
            if try await receiver.chat(id).unreadCount == 0 { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        #expect(try await receiver.chat(id).unreadCount == 0)
    }
    try await b.send(.send(clientId: UUID().uuidString, text: "A real reply", imageId: nil))
    _ = try await liveFrame(b, type: "ack")
    _ = try await liveFrame(a, type: "message")
    #expect(try await first.chatMessages(id).messages.count == 4)
    try await first.blockConnection(id)
    _ = try await liveFrame(b, type: "closed")
    await #expect(throws: APIError.server(404)) { try await second.chat(id) }
    await a.close()
    await b.close()
}

private func livePost(_ config: APIConfiguration, path: String, body: [String: String], token: String? = nil)
    async throws -> Data
{
    var request = URLRequest(url: config.baseURL.appendingPathComponent(path))
    request.httpMethod = "POST"
    request.httpBody = try JSONEncoder().encode(body)
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue("face2face://", forHTTPHeaderField: "Origin")
    if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
    let response = try await URLSessionTransport().send(request)
    guard (200..<300).contains(response.status) else { throw APIError.server(response.status) }
    return response.data
}

private func liveFrame(_ socket: URLSessionChatSocket, type: String) async throws -> ChatServerFrame {
    try await withThrowingTaskGroup(of: ChatServerFrame.self) { group in
        group.addTask {
            for _ in 0..<20 {
                let frame = try await socket.receive()
                switch (type, frame) {
                case ("ready", .ready), ("ack", .acknowledgement), ("message", .message), ("typing", .typing),
                    ("closed", .closed):
                    return frame
                default: continue
                }
            }
            throw LiveChatTimeout()
        }
        group.addTask {
            try await Task.sleep(for: .seconds(10))
            await socket.close()
            throw LiveChatTimeout()
        }
        defer { group.cancelAll() }
        return try await group.next()!
    }
}
