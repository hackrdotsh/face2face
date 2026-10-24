import Foundation

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

public enum APIError: Error, LocalizedError, Equatable {
    case invalidServerURL
    case insecureServerURL
    case unauthenticated
    case invalidResponse
    case server(Int)

    public var errorDescription: String? {
        switch self {
        case .invalidServerURL: "Enter the API's base URL without a path, query, or credentials."
        case .insecureServerURL: "Use an HTTPS API URL. HTTP is only allowed in debug builds."
        case .unauthenticated: "Sign in to continue."
        case .invalidResponse: "The API returned an unexpected response."
        case .server(400): "Check the name, email, and password, then try again."
        case .server(401): "Check your email and password, then try again."
        case .server(429): "Too many attempts. Wait a minute and try again."
        case .server(let status): "The API returned HTTP \(status). Try again."
        }
    }
}

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
}

public struct User: Codable, Sendable, Equatable {
    public let id: String
    public let name: String
}

public struct HTTPResponse: Sendable {
    public let status: Int
    public let data: Data
    public let authToken: String?

    public init(status: Int, data: Data, authToken: String? = nil) {
        self.status = status
        self.data = data
        self.authToken = authToken
    }
}

public protocol HTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws -> HTTPResponse
}

public protocol TokenStore: Sendable {
    func load() async throws -> String?
    func save(_ token: String?) async throws
}

public actor APIClient {
    private let configuration: APIConfiguration
    private let tokens: any TokenStore
    private let transport: any HTTPTransport

    public init(
        configuration: APIConfiguration, tokens: any TokenStore,
        transport: any HTTPTransport = URLSessionTransport()
    ) {
        self.configuration = configuration
        self.tokens = tokens
        self.transport = transport
    }

    public func checkHealth() async throws {
        let response = try await send(path: "health")
        struct Health: Decodable {
            let status: String
            let service: String
        }
        let health = try decode(Health.self, from: response)
        guard health.status == "ok", health.service == "face2face-api" else { throw APIError.invalidResponse }
    }

    public func signIn(email: String, password: String) async throws -> User {
        struct Credentials: Encodable {
            let email: String
            let password: String
        }
        let body = try JSONEncoder().encode(Credentials(email: email, password: password))
        return try await authenticate(path: "api/auth/sign-in/email", body: body)
    }

    public func signUp(name: String, email: String, password: String) async throws -> User {
        struct Registration: Encodable {
            let name: String
            let email: String
            let password: String
        }
        let body = try JSONEncoder().encode(Registration(name: name, email: email, password: password))
        return try await authenticate(path: "api/auth/sign-up/email", body: body)
    }

    public func currentUser() async throws -> User {
        let response = try await send(path: "api/me", authenticated: true)
        return try decode(UserEnvelope.self, from: response).user
    }

    public func signOut() async throws {
        _ = try await send(
            path: "api/auth/sign-out", method: "POST", body: Data("{}".utf8), authenticated: true)
        try await tokens.save(nil)
    }

    private struct UserEnvelope: Decodable { let user: User }

    private func authenticate(path: String, body: Data) async throws -> User {
        let response = try await send(path: path, method: "POST", body: body)
        let user = try decode(UserEnvelope.self, from: response).user
        guard let token = response.authToken, !token.isEmpty else { throw APIError.invalidResponse }
        try await tokens.save(token)
        return user
    }

    private func send(path: String, method: String = "GET", body: Data? = nil, authenticated: Bool = false)
        async throws -> HTTPResponse
    {
        var request = URLRequest(url: configuration.baseURL.appendingPathComponent(path))
        request.httpMethod = method
        request.httpBody = body
        request.timeoutInterval = 10
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("face2face://", forHTTPHeaderField: "Origin")
        if method == "POST" { request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        if authenticated {
            guard let token = try await tokens.load() else { throw APIError.unauthenticated }
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        let response = try await transport.send(request)
        if response.status == 401 && authenticated {
            try await tokens.save(nil)
            throw APIError.unauthenticated
        }
        guard (200..<300).contains(response.status) else { throw APIError.server(response.status) }
        return response
    }

    private func decode<T: Decodable>(_ type: T.Type, from response: HTTPResponse) throws -> T {
        do { return try JSONDecoder().decode(type, from: response.data) } catch {
            throw APIError.invalidResponse
        }
    }
}
