import XCTest

@MainActor
final class ConnectionCelebrationUITests: XCTestCase {
    func testPrivateDialogDismissesAndDoesNotReplayOnForegroundOrNavigation() {
        let app = launch("private")
        let done = app.buttons["connectionCelebrationDismiss"]
        XCTAssertTrue(done.waitForExistence(timeout: 8))
        XCTAssertEqual(app.staticTexts["connectionCelebrationTitle"].label, "You both said hello!")
        XCTAssertGreaterThanOrEqual(done.frame.height, 44)
        capture("private-connection-dialog")
        done.tap()
        XCTAssertTrue(app.buttons["townAccount"].waitForExistence(timeout: 5))
        app.buttons["town-connections"].tap()
        XCTAssertTrue(app.staticTexts["chatsPreviewLabel"].waitForExistence(timeout: 5))
        app.buttons["Done"].tap()
        XCUIDevice.shared.press(.home)
        app.activate()
        XCTAssertTrue(app.buttons["townAccount"].waitForExistence(timeout: 8))
        XCTAssertFalse(done.exists)
    }

    func testPublicDialogSupportsLargeTextAndAccessibleDismissal() {
        let app = launch(
            "public",
            extra: ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
        let done = app.buttons["connectionCelebrationDismiss"]
        XCTAssertTrue(done.waitForExistence(timeout: 8))
        for _ in 0..<5 {
            if done.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(done.isHittable)
        capture("public-connection-large-text")
        done.tap()
        XCTAssertTrue(app.buttons["townAccount"].waitForExistence(timeout: 5))
    }

    func testPeersAcceptanceAppearsWhileWaitingAndDoesNotRepeatOnRefresh() {
        let app = launch(extra: [
            "-town-destination", "encounters", "-encounters-preview-state", "peer-accepts",
        ])
        XCTAssertTrue(app.buttons["connectionCelebrationDismiss"].waitForExistence(timeout: 12))
        XCTAssertEqual(app.staticTexts["connectionCelebrationTitle"].label, "You both said hello!")
        XCTAssertFalse(app.staticTexts["Must stay hidden"].exists)
        capture("peer-accepted-celebration")
        app.buttons["connectionCelebrationDismiss"].tap()
        XCTAssertTrue(app.buttons["encounterOpenChat"].waitForExistence(timeout: 5))
        app.buttons["encountersRefresh"].tap()
        XCTAssertTrue(app.buttons["encounterOpenChat"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["connectionCelebrationDismiss"].exists)
    }

    func testOneSidedAcceptanceDoesNotCelebrate() {
        let app = launch(extra: ["-town-destination", "encounters"])
        let accept = app.buttons["accept-preview-decline"]
        XCTAssertTrue(accept.waitForExistence(timeout: 8))
        for _ in 0..<8 {
            if accept.isHittable { break }
            app.swipeUp()
        }
        accept.tap()
        XCTAssertTrue(app.descendants(matching: .any)["waiting-preview-decline"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["connectionCelebrationDismiss"].exists)
    }

    private func launch(_ kind: String? = nil, extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments =
            ["-town-preview", "-appearance", "light"] + extra
        if let kind { app.launchArguments += ["-connection-celebration-preview", kind] }
        app.launch()
        return app
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
