import Foundation

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

public protocol ChatSocketTransport: Sendable {
    func connect(to url: URL) async throws
    func receive() async throws -> ChatServerFrame
    func send(_ frame: ChatClientFrame) async throws
    func close() async
}

public enum ChatSocketError: Error, Sendable { case closed, disconnected }

public actor URLSessionChatSocket: ChatSocketTransport {
    private var session: URLSession?
    private var task: URLSessionWebSocketTask?
    public init() {}
    public func connect(to url: URL) async throws {
        await close()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        configuration.timeoutIntervalForRequest = 15
        let session = URLSession(
            configuration: configuration, delegate: NoChatRedirects(), delegateQueue: nil)
        var request = URLRequest(url: url)
        request.setValue("face2face://", forHTTPHeaderField: "Origin")
        let task = session.webSocketTask(with: request)
        task.maximumMessageSize = 256 * 1024
        self.session = session
        self.task = task
        task.resume()
    }
    public func receive() async throws -> ChatServerFrame {
        guard let task else { throw ChatSocketError.disconnected }
        do {
            let frame = try await withTaskCancellationHandler {
                try Task.checkCancellation()
                return try await task.receive()
            } onCancel: {
                task.cancel(with: .goingAway, reason: nil)
            }
            let data: Data
            switch frame {
            case .string(let text): data = Data(text.utf8)
            case .data(let bytes): data = bytes
            @unknown default: return .unknown
            }
            return try JSONDecoder().decode(ChatServerFrame.self, from: data)
        } catch {
            if task.closeCode.rawValue >= 4000 { throw ChatSocketError.closed }
            throw ChatSocketError.disconnected
        }
    }
    public func send(_ frame: ChatClientFrame) async throws {
        guard let task else { throw ChatSocketError.disconnected }
        let text =
            frame.type == "ping" ? "ping" : String(decoding: try JSONEncoder().encode(frame), as: UTF8.self)
        do { try await task.send(.string(text)) } catch { throw ChatSocketError.disconnected }
    }
    public func close() async {
        task?.cancel(with: .goingAway, reason: nil)
        session?.invalidateAndCancel()
        task = nil
        session = nil
    }
}

private final class NoChatRedirects: NSObject, URLSessionTaskDelegate {
    func urlSession(
        _ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) { completionHandler(nil) }
}
