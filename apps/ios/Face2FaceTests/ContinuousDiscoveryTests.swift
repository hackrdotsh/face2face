import Face2FaceCore
import XCTest

@testable import Face2Face

private let accountJSON = #"{"user":{"id":"alice","name":"Alice","email":"alice@example.test","avatar":{"seed":"test"}},"onboardingComplete":true}"#
private let leaseJSON = #"{"sessionId":"00112233-4455-4677-8899-aabbccddeeff","token":"ffeeddcc-bbaa-4988-b766-554433221100","expiresAt":1300000,"sessionExpiresAt":2800000,"serverTime":1000000}"#

private actor TestTokens: TokenStore {
    var value: String? = "test-credential"
    func load() -> String? { value }
    func save(_ token: String?) { value = token }
}

private actor DiscoveryTransport: HTTPTransport {
    var paths: [String] = []
    var accountStatus = 200
    var holdStart = false
    private var startRelease: CheckedContinuation<Void, Never>?
    private var startWaiter: CheckedContinuation<Void, Never>?
    private var stopWaiter: CheckedContinuation<Void, Never>?
    private var wantedStops = 1

    func configure(accountStatus: Int = 200, holdStart: Bool = false) {
        self.accountStatus = accountStatus
        self.holdStart = holdStart
    }

    func send(_ request: URLRequest) async throws -> HTTPResponse {
        let path = request.url!.path
        paths.append(path)
        if path == "/api/me" {
            return HTTPResponse(status: accountStatus, data: Data(accountJSON.utf8))
        }
        if path == "/api/discovery/start" {
            if holdStart {
                await withCheckedContinuation { continuation in
                    startRelease = continuation
                    startWaiter?.resume()
                    startWaiter = nil
                }
            }
            let lease = leaseJSON.replacingOccurrences(
                of: "00112233-4455-4677-8899-aabbccddeeff", with: UUID().uuidString.lowercased())
            return HTTPResponse(status: 200, data: Data(lease.utf8))
        }
        if path == "/api/discovery/stop" {
            if paths.filter({ $0 == "/api/discovery/stop" }).count >= wantedStops {
                stopWaiter?.resume()
                stopWaiter = nil
            }
            return HTTPResponse(status: 200, data: Data(#"{"stopped":true}"#.utf8))
        }
        return HTTPResponse(status: 503, data: Data())
    }

    func waitForStart() async {
        if startRelease != nil { return }
        await withCheckedContinuation { startWaiter = $0 }
    }

    func releaseStart() {
        startRelease?.resume()
        startRelease = nil
    }

    func waitForStop(count: Int = 1) async {
        if paths.filter({ $0 == "/api/discovery/stop" }).count >= count { return }
        wantedStops = count
        await withCheckedContinuation { stopWaiter = $0 }
    }
}

@MainActor
final class ContinuousDiscoveryTests: XCTestCase {
    private func preferences() -> UserDefaults {
        let defaults = UserDefaults(suiteName: "discovery-tests-\(UUID())")!
        defaults.set("https://api.example.test", forKey: "apiAddress")
        return defaults
    }

    private func model(_ defaults: UserDefaults, _ transport: DiscoveryTransport) -> ConnectedDiscoveryModel {
        let tokens = TestTokens()
        return ConnectedDiscoveryModel(
            allowsBackground: true, preferences: defaults,
            clientFactory: { APIClient(configuration: $0, tokens: tokens, transport: transport) },
            canAccessCredentials: { true }, supportsBluetooth: true, automaticallyRefreshes: false)
    }

    private func saveOptIn(_ defaults: UserDefaults) throws {
        let optIn = DiscoveryOptIn(accountID: "alice", server: URL(string: "https://api.example.test")!)
        defaults.set(try JSONEncoder().encode(optIn), forKey: "discoveryOptIn")
    }

    func testStoppingDuringStartRevokesTheLateLeaseWithoutRestoringOptIn() async throws {
        let defaults = preferences()
        let transport = DiscoveryTransport()
        await transport.configure(holdStart: true)
        let model = model(defaults, transport)
        let start = Task { await model.start() }
        await transport.waitForStart()
        XCTAssertTrue(model.isEnabled)
        model.stop()
        await transport.releaseStart()
        await start.value
        await transport.waitForStop()
        XCTAssertFalse(model.isEnabled)
        XCTAssertFalse(model.isRunning)
        XCTAssertFalse(model.radio.isRequested)
        XCTAssertNil(defaults.data(forKey: "discoveryOptIn"))
    }

    func testSavedOptInResumesWithFreshAuthenticationAndFailsClosedWithoutRadio() async throws {
        let defaults = preferences()
        try saveOptIn(defaults)
        let transport = DiscoveryTransport()
        let model = model(defaults, transport)
        defer { model.stop() }
        let account = try JSONDecoder().decode(Account.self, from: Data(accountJSON.utf8))
        await model.restore(for: account)
        let paths = await transport.paths
        XCTAssertEqual(paths.prefix(2), ["/api/me", "/api/discovery/start"])
        XCTAssertTrue(model.isEnabled)
        XCTAssertFalse(model.radio.isRequested) // Simulator cannot perform a real Bluetooth exchange.
        XCTAssertTrue(model.discoveryStatus.hasPrefix("Paused"))
        XCTAssertNotNil(defaults.data(forKey: "discoveryOptIn"))
    }

    func testDifferentAccountCannotInheritSavedOptIn() async throws {
        let defaults = preferences()
        try saveOptIn(defaults)
        let transport = DiscoveryTransport()
        let model = model(defaults, transport)
        let account = try JSONDecoder().decode(Account.self, from: Data(accountJSON.replacingOccurrences(of: "alice", with: "bob").utf8))
        await model.restore(for: account)
        let paths = await transport.paths
        XCTAssertTrue(paths.isEmpty)
        XCTAssertFalse(model.isEnabled)
        XCTAssertNil(defaults.data(forKey: "discoveryOptIn"))
    }

    func testRevokedAuthenticationClearsSavedOptIn() async throws {
        let defaults = preferences()
        try saveOptIn(defaults)
        let transport = DiscoveryTransport()
        await transport.configure(accountStatus: 401)
        let model = model(defaults, transport)
        await model.start()
        XCTAssertFalse(model.isEnabled)
        XCTAssertFalse(model.radio.isRequested)
        XCTAssertNil(defaults.data(forKey: "discoveryOptIn"))
    }

    func testOfflineStartKeepsSavedOptInPaused() async throws {
        let defaults = preferences()
        try saveOptIn(defaults)
        let transport = DiscoveryTransport()
        await transport.configure(accountStatus: 503)
        let model = model(defaults, transport)
        defer { model.stop() }
        await model.start()
        XCTAssertTrue(model.isEnabled)
        XCTAssertFalse(model.isRunning)
        XCTAssertTrue(model.discoveryStatus.hasPrefix("Paused"))
        XCTAssertNotNil(defaults.data(forKey: "discoveryOptIn"))
    }

    func testRevokedBluetoothPermissionClearsOptIn() throws {
        let defaults = preferences()
        try saveOptIn(defaults)
        let model = model(defaults, DiscoveryTransport())
        model.radio.onPermissionDenied?()
        XCTAssertFalse(model.isEnabled)
        XCTAssertNil(defaults.data(forKey: "discoveryOptIn"))
    }

    func testToggleOffBeforeQueuedStartCannotReenableDiscovery() async throws {
        let defaults = preferences()
        let transport = DiscoveryTransport()
        let model = model(defaults, transport)
        let account = try JSONDecoder().decode(Account.self, from: Data(accountJSON.utf8))
        model.enable(for: account)
        XCTAssertTrue(model.isEnabled)
        model.stop()
        await Task.yield()
        let paths = await transport.paths
        XCTAssertTrue(paths.isEmpty)
        XCTAssertFalse(model.isEnabled)
        XCTAssertNil(defaults.data(forKey: "discoveryOptIn"))
    }

    func testStopDuringLeaseReplacementAlsoRevokesTheReplacement() async throws {
        let defaults = preferences()
        let transport = DiscoveryTransport()
        let model = model(defaults, transport)
        await model.start()
        XCTAssertTrue(model.isEnabled)
        await transport.configure(holdStart: true)
        let renewal = Task { await model.refresh() }
        await transport.waitForStart()
        model.stop()
        await transport.releaseStart()
        await renewal.value
        await transport.waitForStop(count: 2)
        XCTAssertFalse(model.isEnabled)
        XCTAssertFalse(model.radio.isRequested)
        XCTAssertNil(defaults.data(forKey: "discoveryOptIn"))
    }
}
