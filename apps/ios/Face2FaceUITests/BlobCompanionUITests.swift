import XCTest

@MainActor
final class BlobCompanionUITests: XCTestCase {
    func testCompanionCanStartReturnFromHomeAndStopWithoutDiscovery() {
        let app = launchPreview()
        app.buttons["appSettings"].tap()
        let toggle = app.switches["blobCompanionToggle"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        XCTAssertTrue(toggle.isEnabled)
        if toggle.value as? String == "1" { tapSwitch(toggle) }
        app.buttons["blobCompanionPreview"].tap()
        capture("companion-preview")
        tapSwitch(toggle)
        capture("companion-started")
        XCTAssertEqual(toggle.value as? String, "1", app.debugDescription)
        XCUIDevice.shared.press(.home)
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        XCTAssertTrue(springboard.wait(for: .runningForeground, timeout: 5))
        XCTAssertTrue(springboard.icons.firstMatch.waitForExistence(timeout: 5))
        capture("companion-dynamic-island")
        app.activate()
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        XCTAssertEqual(toggle.value as? String, "1")
        tapSwitch(toggle)
        XCTAssertEqual(toggle.value as? String, "0")
        app.navigationBars["Settings"].buttons["Done"].tap()
        XCTAssertEqual(app.descendants(matching: .any)["townDiscovery"].value as? String, "Off")
    }

    func testWidgetURLReturnsToTown() {
        let app = launchPreview()
        app.buttons["town-forums"].tap()
        XCTAssertTrue(app.staticTexts["Town preview"].waitForExistence(timeout: 4))
        app.open(URL(string: "face2face://town")!)
        XCTAssertTrue(app.buttons["townAccount"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Town preview"].exists)
    }

    func testSignedOutCannotStartCompanionOrUseWidgetLinkToBypassSignIn() {
        let app = XCUIApplication()
        app.launchArguments = ["-apiAddress", "", "-appearance", "light"]
        app.launch()
        XCTAssertTrue(app.buttons["loginStart"].waitForExistence(timeout: 8))
        app.buttons["appSettings"].tap()
        let toggle = app.switches["blobCompanionToggle"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        XCTAssertFalse(toggle.isEnabled)
        app.navigationBars["Settings"].buttons["Done"].tap()
        app.open(URL(string: "face2face://town")!)
        XCTAssertTrue(app.buttons["loginStart"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["townAccount"].exists)
    }

    func testLargeTextCanReachCompanionControls() {
        let app = launchPreview(extra: [
            "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL",
        ])
        app.buttons["appSettings"].tap()
        let toggle = app.switches["blobCompanionToggle"]
        for _ in 0..<8 {
            if toggle.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(toggle.isHittable)
        capture("companion-large-text")
    }

    private func launchPreview(extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-town-preview", "-appearance", "light"] + extra
        app.launch()
        XCTAssertTrue(app.buttons["appSettings"].waitForExistence(timeout: 8))
        return app
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func tapSwitch(_ toggle: XCUIElement) {
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
    }
}
