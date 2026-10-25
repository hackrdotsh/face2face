import XCTest

@testable import Face2Face

@available(iOS 18.0, *)
@MainActor
final class SceneryPerformanceTests: XCTestCase {
    func testTownConstructionPerformance() {
        measure(metrics: [XCTClockMetric(), XCTMemoryMetric()], options: options) {
            autoreleasepool {
                do { _ = try Town3DWorld() } catch { XCTFail("Town setup failed: \(error)") }
            }
        }
    }

    func testForestConstructionPerformance() {
        measure(metrics: [XCTClockMetric(), XCTMemoryMetric()], options: options) {
            autoreleasepool {
                do { _ = try Forest3DWorld() } catch { XCTFail("Forest setup failed: \(error)") }
            }
        }
    }

    private var options: XCTMeasureOptions {
        let options = XCTMeasureOptions()
        options.iterationCount = 5
        return options
    }
}
