import Foundation
import Testing

@testable import Face2FaceCore

private let chatMessageJSON =
    #"{"id":"message","clientId":"send-1","from":"you","text":"Hello","image":null,"createdAt":"2026-10-25T10:00:00.000Z"}"#

@Test func chatHistoryTicketsAndPhotosUseExistingAuthenticatedEndpoints() async throws {
    let transport = StubTransport([
        response(json: #"{"messages":[],"hasMore":true}"#),
        response(json: #"{"ticket":"short-lived.ticket","expiresAt":"2026-10-25T11:00:00Z"}"#),
        response(
            json:
                #"{"image":{"id":"photo","variants":{"original":{"width":2,"height":1,"path":"/media/chats/id/photo/original?expires=1&signature=s"},"preview":{"width":2,"height":1,"path":"/media/chats/id/photo/preview"},"thumb":{"width":2,"height":1,"path":"/media/chats/id/photo/thumb"}}}}"#
        ),
    ])
    let client = APIClient(
        configuration: try configuration(), tokens: MemoryTokens("bearer-secret"), transport: transport)
    let page = try await client.chatMessages("connection", before: "message 1")
    #expect(page.hasMore)
    let socket = try await client.chatSocketURL("connection")
    #expect(socket.scheme == "wss")
    #expect(socket.host == "api.example.test")
    #expect(socket.path == "/api/chats/connection/socket")
    #expect(!socket.absoluteString.contains("bearer-secret"))
    #expect(
        URLComponents(url: socket, resolvingAgainstBaseURL: false)?.queryItems == [
            URLQueryItem(name: "ticket", value: "short-lived.ticket")
        ])
    let photo = Data([0xFF, 0xD8, 0xFF, 0xD9])
    #expect(try await client.uploadChatPhoto("connection", jpeg: photo).id == "photo")
    let requests = await transport.requests
    #expect(
        requests.map { $0.url?.path } == [
            "/api/chats/connection/messages", "/api/chats/connection/ticket", "/api/chats/connection/images",
        ])
    #expect(requests.allSatisfy { $0.value(forHTTPHeaderField: "Authorization") == "Bearer bearer-secret" })
    #expect(String(decoding: requests[2].httpBody ?? Data(), as: UTF8.self).contains("name=\"image\""))
    #expect(requests[2].httpBody?.range(of: photo) != nil)
}

@Test func chatTranscriptSettlesLostAcknowledgementsAndDeduplicatesReplays() throws {
    let pending = PendingChatMessage(text: "Hello", photo: nil)
    let json = chatMessageJSON.replacingOccurrences(of: "send-1", with: pending.id)
    let message = try JSONDecoder().decode(ChatMessage.self, from: Data(json.utf8))
    var transcript = ChatTranscript()
    transcript.pending = [pending]
    transcript.merge([message, message])
    #expect(transcript.messages.count == 1)
    #expect(transcript.pending.isEmpty)
    transcript.merge([message])
    #expect(transcript.messages.count == 1)
}

@Test func chatFramesPreserveIdempotencyAndRecognizeClosure() throws {
    let frame = ChatClientFrame.send(clientId: "same-id", text: "hello", imageId: "image")
    let object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(frame)) as? [String: String]
    #expect(object?["clientId"] == "same-id")
    #expect(object?["imageId"] == "image")
    let ack = try JSONDecoder().decode(
        ChatServerFrame.self,
        from: Data("{\"type\":\"ack\",\"clientId\":\"send-1\",\"message\":\(chatMessageJSON)}".utf8))
    guard case .acknowledgement(let id, let message) = ack else {
        Issue.record("Expected acknowledgement")
        return
    }
    #expect(id == "send-1" && message.from == .you)
    let closed = try JSONDecoder().decode(ChatServerFrame.self, from: Data(#"{"type":"closed"}"#.utf8))
    guard case .closed = closed else {
        Issue.record("Expected terminal closure")
        return
    }
}

@Test func privateChatNeverUsesUnexpectedPeerIdentity() throws {
    let json =
        #"{"id":"chat","connection":{"id":"chat","status":"private","sharedInterests":[],"expiresAt":"2026-10-26T00:00:00Z","them":{"userId":"peer","name":"Must stay hidden","avatar":{"seed":"AAAAAAAAAAAAAAAAAAAAAA"}}},"lastMessage":null,"unreadCount":3}"#
    let chat = try JSONDecoder().decode(ChatSummary.self, from: Data(json.utf8))
    #expect(chat.title == "Anonymous connection")
    #expect(chat.connection.publicTownFriend == nil)
}

@Test func chatRejectsMissingCredentialsAndUnsafePaths() async throws {
    let transport = StubTransport([])
    let client = APIClient(configuration: try configuration(), tokens: MemoryTokens(), transport: transport)
    await #expect(throws: APIError.unauthenticated) { try await client.chats() }
    for id in ["", "..", "../other", "a/b"] {
        await #expect(throws: APIError.invalidResponse) { try await client.chatMessages(id) }
    }
    #expect(await transport.requests.isEmpty)
}
