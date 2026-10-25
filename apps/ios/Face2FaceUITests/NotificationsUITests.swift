import XCTest

@MainActor
final class NotificationsUITests: XCTestCase {
    func testBellOpensThemedInboxAndReturnsToTown() {
        let app = launch()
        let bell = app.buttons["townNotifications"]
        XCTAssertTrue(bell.waitForExistence(timeout: 8))
        XCTAssertGreaterThanOrEqual(bell.frame.width, 44)
        XCTAssertGreaterThanOrEqual(bell.frame.height, 44)
        bell.tap()
        XCTAssertTrue(app.staticTexts["notificationsPreviewLabel"].waitForExistence(timeout: 4))
        XCTAssertTrue(app.buttons["notification-preview-0"].waitForExistence(timeout: 4))
        capture("notifications-populated")
        app.buttons["notification-preview-0"].tap()
        XCTAssertTrue(app.navigationBars["Recently encountered"].waitForExistence(timeout: 4))
        app.buttons["Done"].tap()
        XCTAssertTrue(app.buttons["notificationsBack"].waitForExistence(timeout: 4))
        app.buttons["notificationsRefresh"].tap()
        XCTAssertTrue(app.buttons["notification-preview-0"].waitForExistence(timeout: 4))
        app.buttons["notificationsBack"].tap()
        XCTAssertTrue(bell.waitForExistence(timeout: 4))
    }

    func testEmptyAndErrorAreDifferentStates() {
        let empty = launch(state: "empty")
        empty.buttons["townNotifications"].tap()
        XCTAssertTrue(empty.staticTexts["notificationsEmpty"].waitForExistence(timeout: 4))
        XCTAssertFalse(empty.buttons["notificationsRetry"].exists)
        capture("notifications-empty")
        empty.terminate()
        let error = launch(state: "error")
        error.buttons["townNotifications"].tap()
        XCTAssertTrue(error.buttons["notificationsRetry"].waitForExistence(timeout: 4))
        XCTAssertFalse(error.staticTexts["notificationsEmpty"].exists)
        error.buttons["notificationsRetry"].tap()
        XCTAssertTrue(error.buttons["notificationsRetry"].waitForExistence(timeout: 4))
        capture("notifications-error")
    }

    func testLargeTextInboxAndForumRouting() {
        let app = launch(extra: [
            "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL",
        ])
        app.buttons["townNotifications"].tap()
        XCTAssertTrue(app.buttons["notificationsBack"].waitForExistence(timeout: 4))
        let event = app.buttons["notification-preview-2"]
        for _ in 0..<6 {
            if event.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(event.isHittable)
        capture("notifications-large-text")
        event.tap()
        XCTAssertTrue(app.navigationBars["Forums"].waitForExistence(timeout: 4))
    }

    private func launch(state: String? = nil, extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-town-preview", "-appearance", "light"] + extra
        if let state { app.launchArguments += ["-notifications-preview-state", state] }
        app.launch()
        XCTAssertTrue(app.buttons["townNotifications"].waitForExistence(timeout: 8))
        return app
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
