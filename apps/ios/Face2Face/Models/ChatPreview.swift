import Face2FaceCore
import Foundation

#if DEBUG
    enum ChatPreview {
        static func chats() throws -> [ChatSummary] {
            let json = """
                [{"id":"preview-ava","connection":{"id":"preview-ava","status":"public","sharedInterests":["music","coffee"],
                "them":{"userId":"ava","name":"Ava","age":26,"interests":["music","coffee"],"avatar":{"seed":"AAAAAAAAAAAAAAAAAAAAAA"}},
                "expiresAt":"2026-10-26T00:00:00Z"},"lastMessage":null,"unreadCount":2},
                {"id":"preview-private","connection":{"id":"preview-private","status":"private","sharedInterests":["hiking"],
                "them":null,"expiresAt":"2026-10-26T00:00:00Z"},"lastMessage":null,"unreadCount":0},
                {"id":"preview-cleo","connection":{"id":"preview-cleo","status":"public","sharedInterests":["coffee"],
                "them":{"userId":"cleo","name":"Cleo","age":24,"interests":["coffee"],"avatar":{"seed":"AQIDBAUGBwgJCgsMDQ4PEA"}},
                "expiresAt":"2026-10-26T00:00:00Z"},"lastMessage":null,"unreadCount":0},
                {"id":"preview-noor","connection":{"id":"preview-noor","status":"public","sharedInterests":["music"],
                "them":{"userId":"noor","name":"Noor","age":28,"interests":["music"],"avatar":{"seed":"AQIDBAUGBwgJCgsMDQ4PEA"}},
                "expiresAt":"2026-10-26T00:00:00Z"},"lastMessage":null,"unreadCount":0}]
                """
            return try JSONDecoder().decode([ChatSummary].self, from: Data(json.utf8))
        }
        static func messages(chatID: String) throws -> [ChatMessage] {
            let greeting =
                chatID == "preview-private"
                ? "Hey! Do you have a favorite hiking trail?" : "Hey! Lovely running into you."
            var rows: [[String: Any]] = [
                [
                    "id": "preview-1", "from": "them", "clientId": NSNull(), "text": greeting,
                    "image": NSNull(), "createdAt": "2026-10-25T10:00:00.000Z",
                ],
                [
                    "id": "preview-2", "from": "you", "clientId": "sample-send",
                    "text": "A little hello goes a long way ☕", "image": NSNull(),
                    "createdAt": "2026-10-25T10:01:00.000Z",
                ],
                [
                    "id": "preview-3", "from": "them", "clientId": NSNull(),
                    "text": "We should grab a coffee sometime!", "image": NSNull(),
                    "createdAt": "2026-10-25T10:02:00.000Z",
                ],
            ]
            let formatter = ISO8601DateFormatter()
            for index in rows.indices {
                rows[index]["createdAt"] = formatter.string(
                    from: Date().addingTimeInterval(Double(index - rows.count) * 60))
            }
            return try JSONDecoder().decode(
                [ChatMessage].self, from: JSONSerialization.data(withJSONObject: rows))
        }
        static func acknowledge(_ pending: PendingChatMessage) throws -> ChatMessage {
            let row: [String: Any] = [
                "id": "sample-message-\(pending.id)", "clientId": pending.id, "from": "you",
                "text": pending.text as Any? ?? NSNull(), "image": NSNull(),
                "createdAt": ISO8601DateFormatter().string(from: Date()),
            ]
            return try JSONDecoder().decode(
                ChatMessage.self, from: JSONSerialization.data(withJSONObject: row))
        }
    }
#endif
