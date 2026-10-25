import XCTest

@MainActor
final class PushSetupUITests: XCTestCase {
    func testSettingsExplainsSetupWithoutRegisteringARealPreviewDevice() {
        let app = XCUIApplication()
        app.launchArguments = ["-town-preview", "-appearance", "light"]
        app.launch()
        XCTAssertTrue(app.buttons["appSettings"].waitForExistence(timeout: 8))
        app.buttons["appSettings"].tap()
        let retry = app.buttons["pushRetrySetup"]
        for _ in 0..<8 {
            if retry.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(retry.exists)
        XCTAssertFalse(retry.isEnabled)
        XCTAssertTrue(app.staticTexts["pushServerSetup"].exists)
        XCTAssertTrue(app.staticTexts["Preview — no real push setup tested"].exists)
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = "push-setup-preview"
        attachment.lifetime = .keepAlways
        add(attachment)
        app.navigationBars["Settings"].buttons["Done"].tap()
        XCTAssertTrue(app.buttons["townAccount"].waitForExistence(timeout: 5))
    }
}
