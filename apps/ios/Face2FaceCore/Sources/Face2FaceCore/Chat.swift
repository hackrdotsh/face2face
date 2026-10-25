import Foundation

public struct ChatImage: Codable, Sendable, Equatable, Identifiable {
    public struct Variant: Codable, Sendable, Equatable {
        public let width: Int
        public let height: Int
        public let path: String
    }
    public struct Variants: Codable, Sendable, Equatable {
        public let original: Variant
        public let preview: Variant
        public let thumb: Variant
    }
    public let id: String
    public let variants: Variants
}

public struct ChatMessage: Codable, Sendable, Equatable, Identifiable {
    public enum Sender: String, Codable, Sendable { case you, them }
    public let id: String
    public let clientId: String?
    public let from: Sender
    public let text: String?
    public let image: ChatImage?
    public let createdAt: String
}

public struct ChatSummary: Decodable, Sendable, Identifiable {
    public let id: String
    public let connection: TownConnection
    public let lastMessage: ChatMessage?
    public let unreadCount: Int
    public var title: String { connection.publicTownFriend?.name ?? "Anonymous connection" }
}

public struct ChatMessagePage: Decodable, Sendable {
    public let messages: [ChatMessage]
    public let hasMore: Bool
}

public struct ChatClientFrame: Encodable, Sendable {
    public let type: String
    public var clientId: String?
    public var text: String?
    public var imageId: String?
    public var state: String?
    public var messageId: String?

    public static func send(clientId: String, text: String?, imageId: String?) -> Self {
        Self(type: "send", clientId: clientId, text: text, imageId: imageId)
    }
    public static func typing(_ started: Bool) -> Self {
        Self(type: "typing", state: started ? "started" : "stopped")
    }
    public static func read(_ id: String) -> Self { Self(type: "read", messageId: id) }
    public static var ping: Self { Self(type: "ping") }
}

public enum ChatServerFrame: Decodable, Sendable {
    case ready, pong, closed, unknown
    case acknowledgement(String, ChatMessage)
    case message(ChatMessage)
    case typing(Bool)
    case error(String, String?)

    private enum Keys: String, CodingKey { case type, clientId, message, state, error }
    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: Keys.self)
        switch try values.decode(String.self, forKey: .type) {
        case "ready": self = .ready
        case "pong": self = .pong
        case "closed": self = .closed
        case "ack":
            self = .acknowledgement(
                try values.decode(String.self, forKey: .clientId),
                try values.decode(ChatMessage.self, forKey: .message))
        case "message": self = .message(try values.decode(ChatMessage.self, forKey: .message))
        case "typing": self = .typing(try values.decode(String.self, forKey: .state) == "started")
        case "error":
            self = .error(
                try values.decode(String.self, forKey: .error),
                try values.decodeIfPresent(String.self, forKey: .clientId))
        default: self = .unknown
        }
    }
}

public struct PendingChatMessage: Identifiable, Sendable {
    public enum Status: String, Sendable { case uploading, sending, failed }
    public let id: String
    public let text: String?
    public var photo: Data?
    public var imageId: String?
    public var status: Status
    public init(text: String?, photo: Data?) {
        id = UUID().uuidString
        self.text = text
        self.photo = photo
        status = photo == nil ? .sending : .uploading
    }
}

/// Retry preserves client IDs; matching history also settles sends whose acknowledgement was lost.
public struct ChatTranscript: Sendable {
    public private(set) var messages: [ChatMessage] = []
    public var pending: [PendingChatMessage] = []
    public init() {}
    public mutating func merge(_ incoming: [ChatMessage]) {
        var byID = Dictionary(messages.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
        for message in incoming { byID[message.id] = message }
        messages = byID.values.sorted {
            $0.createdAt == $1.createdAt ? $0.id < $1.id : $0.createdAt < $1.createdAt
        }
        let settled = Set(incoming.filter { $0.from == .you }.compactMap(\.clientId))
        pending.removeAll { settled.contains($0.id) }
    }
}

extension APIClient {
    public func chats() async throws -> [ChatSummary] {
        struct Result: Decodable { let chats: [ChatSummary] }
        return try decode(
            Result.self, from: try await send(APIRequest(path: "api/chats", authenticated: true))
        )
        .chats.filter { $0.connection.isFriend }
    }
    public func chat(_ id: String) async throws -> ChatSummary {
        struct Result: Decodable { let chat: ChatSummary }
        let result = try decode(
            Result.self, from: try await send(APIRequest(path: try Self.chatPath(id), authenticated: true))
        ).chat
        guard result.connection.isFriend else { throw APIError.server(404) }
        return result
    }
    public func chatMessages(_ id: String, before: String? = nil) async throws -> ChatMessagePage {
        try decode(
            ChatMessagePage.self,
            from: try await send(
                APIRequest(
                    path: try Self.chatPath(id) + "/messages",
                    query: before.map { [URLQueryItem(name: "before", value: $0)] } ?? [], authenticated: true
                )))
    }
    public func chatSocketURL(_ id: String) async throws -> URL {
        struct Ticket: Decodable {
            let ticket: String
            let expiresAt: String
        }
        let path = try Self.chatPath(id)
        let ticket = try decode(
            Ticket.self, from: try await post(path + "/ticket", [String: String](), authenticated: true))
        var url = URLComponents(
            url: configurationURL.appendingPathComponent(path + "/socket"), resolvingAgainstBaseURL: false)
        url?.scheme = configurationURL.scheme == "https" ? "wss" : "ws"
        url?.queryItems = [URLQueryItem(name: "ticket", value: ticket.ticket)]
        guard let result = url?.url, !ticket.ticket.isEmpty else { throw APIError.invalidResponse }
        return result
    }
    public func uploadChatPhoto(_ id: String, jpeg: Data) async throws -> ChatImage {
        guard !jpeg.isEmpty, jpeg.count <= 15 * 1024 * 1024 else { throw APIError.server(413) }
        let form = MultipartForm(
            fileField: "image", fileName: "photo.jpg", contentType: "image/jpeg", data: jpeg)
        struct Result: Decodable { let image: ChatImage }
        return try decode(
            Result.self,
            from: try await send(
                APIRequest(
                    path: try Self.chatPath(id) + "/images",
                    method: "POST", body: form.body, contentType: form.contentType, timeout: 60,
                    authenticated: true))
        ).image
    }
    private static func chatPath(_ id: String) throws -> String {
        guard !id.isEmpty, id.utf8.count <= 200, !id.contains("/"), id != ".", id != "..",
            let component = id.addingPercentEncoding(
                withAllowedCharacters: .alphanumerics.union(CharacterSet(charactersIn: "-._~")))
        else { throw APIError.invalidResponse }
        return "api/chats/" + component
    }
}
