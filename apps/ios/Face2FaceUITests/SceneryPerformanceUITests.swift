import XCTest

@MainActor
final class SceneryPerformanceUITests: XCTestCase {
    func testIdleTownCPUPerformance() {
        let app = XCUIApplication()
        app.launchArguments = ["-town-preview", "-appearance", "light", "-forest3DEnabled", "YES"]
        app.launch()
        XCTAssertTrue(app.buttons["town-forums"].waitForExistence(timeout: 10))
        let options = XCTMeasureOptions()
        options.iterationCount = 5
        measure(
            metrics: [XCTCPUMetric(application: app), XCTMemoryMetric(application: app)], options: options
        ) {
            Thread.sleep(forTimeInterval: 3)
        }
    }
}
