import Foundation

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

public struct APIConfiguration: Sendable {
    public let baseURL: URL

    public init(address: String, allowInsecureHTTP: Bool = false) throws {
        guard var components = URLComponents(string: address.trimmingCharacters(in: .whitespacesAndNewlines)),
            let scheme = components.scheme?.lowercased(),
            ["http", "https"].contains(scheme),
            let host = components.host, !host.isEmpty,
            components.user == nil, components.password == nil,
            components.query == nil, components.fragment == nil,
            components.path.isEmpty || components.path == "/"
        else { throw APIError.invalidServerURL }
        guard scheme == "https" || allowInsecureHTTP else { throw APIError.insecureServerURL }
        components.scheme = scheme
        components.path = ""
        guard let url = components.url else { throw APIError.invalidServerURL }
        baseURL = url
    }

    /// Resolves a signed media path, which carries its own query, against the API server.
    public func mediaURL(for path: String) -> URL? {
        URL(string: path, relativeTo: baseURL)?.absoluteURL
    }
}

public struct HTTPResponse: Sendable {
    public let status: Int
    public let data: Data
    public let authToken: String?
    public let cookies: [String: String]

    public init(status: Int, data: Data, authToken: String? = nil, cookies: [String: String] = [:]) {
        self.status = status
        self.data = data
        self.authToken = authToken
        self.cookies = cookies
    }
}

public protocol HTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws -> HTTPResponse
}

public protocol TokenStore: Sendable {
    func load() async throws -> String?
    func save(_ token: String?) async throws
}

struct APIRequest {
    var path: String
    var method = "GET"
    var query: [URLQueryItem] = []
    var body: Data?
    var contentType = "application/json"
    var timeout: TimeInterval = 10
    var authenticated = false
    var cookie: String?
}

public actor APIClient {
    private let configuration: APIConfiguration
    private let tokens: any TokenStore
    private let transport: any HTTPTransport
    var configurationURL: URL { configuration.baseURL }

    public init(
        configuration: APIConfiguration, tokens: any TokenStore,
        transport: any HTTPTransport = URLSessionTransport()
    ) {
        self.configuration = configuration
        self.tokens = tokens
        self.transport = transport
    }

    public func checkHealth() async throws {
        let response = try await send(APIRequest(path: "health"))
        struct Health: Decodable {
            let status: String
            let service: String
        }
        let health = try decode(Health.self, from: response)
        guard health.status == "ok", health.service == "face2face-api" else { throw APIError.invalidResponse }
    }

    public func currentAccount() async throws -> Account {
        try decode(Account.self, from: try await send(APIRequest(path: "api/me", authenticated: true)))
    }

    /// A run-scoped client cannot upload old observations as a newly signed-in account.
    /// The snapshot lives only in memory. The persistent credential stays in Keychain.
    public func capturingCurrentCredential() async throws -> APIClient {
        guard let credential = try await tokens.load() else { throw APIError.unauthenticated }
        return APIClient(
            configuration: configuration, tokens: CredentialSnapshot(credential), transport: transport)
    }

    private actor CredentialSnapshot: TokenStore {
        private var credential: String?
        init(_ credential: String) { self.credential = credential }
        func load() -> String? { credential }
        func save(_ token: String?) { credential = token }
    }

    /// Compares account context without exposing either credential. Only call with Keychain unlocked.
    public func usesSameCredential(as other: APIClient) async throws -> Bool {
        guard configuration.baseURL == other.configuration.baseURL else { return false }
        guard let current = try await tokens.load() else { return false }
        return try await other.credentialForComparison() == current
    }

    private func credentialForComparison() async throws -> String? {
        try await tokens.load()
    }

    func send(_ request: APIRequest) async throws -> HTTPResponse {
        var urlRequest = URLRequest(url: try url(for: request))
        urlRequest.httpMethod = request.method
        urlRequest.httpBody = request.body
        urlRequest.timeoutInterval = request.timeout
        urlRequest.setValue("application/json", forHTTPHeaderField: "Accept")
        urlRequest.setValue("face2face://", forHTTPHeaderField: "Origin")
        if request.body != nil {
            urlRequest.setValue(request.contentType, forHTTPHeaderField: "Content-Type")
        }
        if let cookie = request.cookie { urlRequest.setValue(cookie, forHTTPHeaderField: "Cookie") }
        if request.authenticated {
            guard let token = try await tokens.load() else { throw APIError.unauthenticated }
            urlRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        let response = try await transport.send(urlRequest)
        if response.status == 401 && request.authenticated {
            try await tokens.save(nil)
            throw APIError.unauthenticated
        }
        guard (200..<300).contains(response.status) else {
            throw APIError.from(status: response.status, body: response.data)
        }
        return response
    }

    func post(_ path: String, _ body: some Encodable, authenticated: Bool = false, cookie: String? = nil)
        async throws -> HTTPResponse
    {
        try await send(
            APIRequest(
                path: path, method: "POST", body: try JSONEncoder().encode(body),
                authenticated: authenticated,
                cookie: cookie))
    }

    func saveSessionToken(from response: HTTPResponse) async throws {
        guard let token = response.authToken, !token.isEmpty else { throw APIError.invalidResponse }
        try await tokens.save(token)
    }

    func clearSessionToken() async throws {
        try await tokens.save(nil)
    }

    func decode<T: Decodable>(_ type: T.Type, from response: HTTPResponse) throws -> T {
        do { return try JSONDecoder().decode(type, from: response.data) } catch {
            throw APIError.invalidResponse
        }
    }

    private func url(for request: APIRequest) throws -> URL {
        let url = configuration.baseURL.appendingPathComponent(request.path)
        guard !request.query.isEmpty else { return url }
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            throw APIError.invalidServerURL
        }
        components.queryItems = request.query
        guard let withQuery = components.url else { throw APIError.invalidServerURL }
        return withQuery
    }
}
