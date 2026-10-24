import Foundation

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

public struct URLSessionTransport: HTTPTransport {
    private let session: URLSession

    public init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        session = URLSession(configuration: configuration, delegate: NoRedirects(), delegateQueue: nil)
    }

    public func send(_ request: URLRequest) async throws -> HTTPResponse {
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        return HTTPResponse(
            status: response.statusCode, data: data,
            authToken: response.value(forHTTPHeaderField: "set-auth-token"),
            cookies: response.url.map { Self.cookies(fromHeaders: response.allHeaderFields, for: $0) } ?? [:])
    }

    static func cookies(fromHeaders allHeaderFields: [AnyHashable: Any], for url: URL) -> [String: String] {
        var headers: [String: String] = [:]
        for (name, value) in allHeaderFields {
            if let name = name as? String, let value = value as? String { headers[name] = value }
        }
        let parsed = HTTPCookie.cookies(withResponseHeaderFields: headers, for: url)
        return Dictionary(parsed.map { ($0.name, $0.value) }, uniquingKeysWith: { _, last in last })
    }
}

private final class NoRedirects: NSObject, URLSessionTaskDelegate {
    func urlSession(
        _ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}
