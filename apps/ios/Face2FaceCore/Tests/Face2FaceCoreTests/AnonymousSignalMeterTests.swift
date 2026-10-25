import Foundation
import Testing

@testable import Face2FaceCore

@Test func signalRejectsUnavailableAndImplausibleRSSI() {
    var meter = AnonymousSignalMeter()
    for rssi in [127, 128, -128, 21, 500] {
        #expect(meter.observe(rssi: rssi, uptime: 1, date: .now) == nil)
    }
    #expect(meter.observe(rssi: -60, uptime: .nan, date: .now) == nil)
}

@Test func signalAcceptsVeryWeakAndVeryStrongValidReadings() {
    for rssi in [-127, -110, 0, 20] {
        var meter = AnonymousSignalMeter()
        let sample = meter.observe(rssi: rssi, uptime: 1, date: .now)
        #expect(sample?.levels == [rssi >= -60 ? 4 : 1])
    }
}

@Test func signalQuantizesAndCoalescesWithoutKeepingRawRSSI() {
    var meter = AnonymousSignalMeter()
    let now = Date()
    #expect(meter.observe(rssi: -95, uptime: 0, date: now)?.levels == [1])
    #expect(meter.observe(rssi: -90, uptime: 1, date: now) == nil)
    #expect(meter.observe(rssi: -55, uptime: 3, date: now)?.levels.count == 2)
    for index in 2..<30 {
        let sample = meter.observe(rssi: -45, uptime: Double(index * 3), date: now)
        #expect((sample?.levels.count ?? 0) <= 9)
        #expect(sample?.levels.allSatisfy { (1...4).contains($0) } == true)
    }
}

@Test func signalExpiresAndClockResetFailsClosed() {
    var meter = AnonymousSignalMeter()
    _ = meter.observe(rssi: -50, uptime: 10, date: .now)
    #expect(meter.expire(uptime: 21) == nil)
    #expect(meter.expire(uptime: 22)?.levels == [])
    _ = meter.observe(rssi: -50, uptime: 30, date: .now)
    #expect(meter.expire(uptime: 1)?.levels == [])
}

@Test func signalAfterAGapDoesNotBlendOldSamplesIntoANewObservation() {
    var meter = AnonymousSignalMeter()
    _ = meter.observe(rssi: -40, uptime: 0, date: .now)
    #expect(meter.observe(rssi: -95, uptime: 20, date: .now)?.levels == [1])
}

@Test func blobPersonalityIsBoundedAndReduceMotionIsStill() {
    for seed in ["AAAAAAAAAAAAAAAAAAAAAA", "AQIDBAUGBwgJCgsMDQ4PEA", "invalid!"] {
        let motion = BlobPlayMotion(seed: seed)
        for time in stride(from: 0.0, through: 60.0, by: 0.1) {
            let pose = motion.pose(at: time)
            #expect((0.94...1.06).contains(pose.xScale))
            #expect((0.94...1.06).contains(pose.yScale))
            #expect((0...0.1).contains(pose.lift))
            #expect((-7...7).contains(pose.tilt))
        }
        let still = motion.pose(at: 12, reducedMotion: true)
        #expect(still.xScale == 1 && still.yScale == 1 && still.lift == 0 && still.tilt == 0)
        #expect(motion.pose(at: .nan).lift == 0)
    }
}
