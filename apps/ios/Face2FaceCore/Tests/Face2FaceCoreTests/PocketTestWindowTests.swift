import Foundation
import Testing

@testable import Face2FaceCore

private let pocketStart = Date(timeIntervalSince1970: 1_000)

@Test func pocketConsentExpiresEvenIfNoTimerFiresWhileSuspended() {
    let window = PocketTestWindow(at: pocketStart, uptime: 2_000)
    #expect(window.remaining(at: pocketStart, uptime: 2_000) == 300)
    #expect(window.remaining(at: pocketStart.addingTimeInterval(90), uptime: 2_090) == 210)
    #expect(window.remaining(at: pocketStart.addingTimeInterval(300), uptime: 2_300) == 0)
    #expect(window.remaining(at: pocketStart.addingTimeInterval(900), uptime: 2_900) == 0)
}

@Test func pocketClockRollbackCannotExtendTheConsentWindow() {
    let window = PocketTestWindow(at: pocketStart, uptime: 2_000)
    #expect(window.remaining(at: pocketStart.addingTimeInterval(-1), uptime: 2_010) == 0)
    // The wall clock still reads after Start, but uptime proves two minutes passed.
    #expect(window.remaining(at: pocketStart.addingTimeInterval(20), uptime: 2_120) == 180)
    #expect(window.remaining(at: pocketStart.addingTimeInterval(20), uptime: 2_301) == 0)
}

@Test func pocketClockJumpAndResetUptimeFailClosed() {
    let window = PocketTestWindow(at: pocketStart, uptime: 2_000)
    #expect(window.remaining(at: pocketStart.addingTimeInterval(600), uptime: 2_010) == 0)
    #expect(window.remaining(at: pocketStart.addingTimeInterval(10), uptime: 12) == 0)
}

@Test func pocketInvalidClockInputsCannotEnableTheRadio() {
    let window = PocketTestWindow(at: pocketStart, uptime: .nan)
    #expect(window.remaining(at: pocketStart, uptime: 2_000) == 0)
    let valid = PocketTestWindow(at: pocketStart, uptime: 2_000)
    #expect(valid.remaining(at: pocketStart, uptime: .infinity) == 0)
    #expect(valid.remaining(at: pocketStart, uptime: -.infinity) == 0)
}

@Test func pocketCheckpointPersistsOnlyNonSecretConsentMetadata() throws {
    let window = PocketTestWindow(at: pocketStart, uptime: 2_000)
    let data = try JSONEncoder().encode(window)
    #expect(try JSONDecoder().decode(PocketTestWindow.self, from: data) == window)
    let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    #expect(Set(object.keys) == Set(["id", "startedAt", "startedUptime"]))
    let recovered = try JSONDecoder().decode(PocketTestWindow.self, from: data)
    #expect(recovered.remaining(at: pocketStart.addingTimeInterval(301), uptime: 2_301) == 0)
}
