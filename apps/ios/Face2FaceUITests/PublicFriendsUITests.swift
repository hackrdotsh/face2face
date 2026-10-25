import XCTest

@MainActor
final class PublicFriendsUITests: XCTestCase {
    func testOnlyPublicFriendsBecomeNPCsAndOpenCompactProfiles() {
        let app = launch()
        let ava = app.buttons["town-friend-preview-ava"]
        XCTAssertTrue(ava.waitForExistence(timeout: 8))
        XCTAssertEqual(
            app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'town-friend-' ")).count, 3)
        for status in ["private", "pending", "blocked", "expired"] {
            XCTAssertFalse(app.buttons["town-friend-hidden-\(status)"].exists)
            XCTAssertFalse(app.staticTexts["Hidden \(status)"].exists)
        }
        XCTAssertEqual(ava.value as? String, "Status: Looking for a hiking buddy this weekend")
        XCTAssertEqual(app.buttons["town-friend-preview-cleo"].value as? String, "")
        XCTAssertGreaterThanOrEqual(ava.frame.width, 44)
        XCTAssertGreaterThanOrEqual(ava.frame.height, 44)
        capture("public-friend-npcs")
        ava.tap()
        let name = app.staticTexts["publicProfileName"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        XCTAssertEqual(name.label, "Ava, 26")
        XCTAssertTrue(app.staticTexts["Public connection"].exists)
        let statusMessage = app.staticTexts["publicProfileStatusMessage"]
        XCTAssertTrue(statusMessage.exists)
        XCTAssertEqual(statusMessage.label, "Status: Looking for a hiking buddy this weekend")
        capture("compact-public-profile")
        app.buttons["publicProfileClose"].tap()
        XCTAssertTrue(ava.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["town-forums"].isHittable)
    }

    func testRevokedPublicConnectionCannotOpenACachedProfile() {
        let app = launch(state: "revoked")
        let ava = app.buttons["town-friend-preview-ava"]
        XCTAssertTrue(ava.waitForExistence(timeout: 8))
        ava.tap()
        let status = app.staticTexts["publicProfileStatus"]
        XCTAssertTrue(status.waitForExistence(timeout: 5))
        XCTAssertEqual(status.label, "Profile no longer available")
        XCTAssertFalse(app.staticTexts["publicProfileName"].exists)
        capture("public-profile-revoked")
        app.buttons["publicProfileClose"].tap()
        XCTAssertFalse(ava.exists)
    }

    func testEmptyAndFailedLoadsDoNotBlockTheTown() {
        let empty = launch(state: "empty")
        XCTAssertTrue(empty.buttons["town-forums"].waitForExistence(timeout: 8))
        XCTAssertEqual(
            empty.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'town-friend-' ")).count, 0)
        empty.terminate()
        let failed = launch(state: "error")
        XCTAssertTrue(failed.buttons["townFriendsRetry"].waitForExistence(timeout: 8))
        XCTAssertEqual(
            failed.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'town-friend-' ")).count, 0)
        XCTAssertTrue(failed.buttons["town-forums"].isHittable)
    }

    func testLargeTextCanOpenPublicFriendWithoutChasingAMovingTarget() {
        let app = launch(extra: [
            "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL",
        ])
        let ava = app.buttons["town-friend-preview-ava"]
        XCTAssertTrue(ava.waitForExistence(timeout: 8))
        for _ in 0..<6 {
            if ava.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(ava.isHittable)
        ava.tap()
        XCTAssertTrue(app.staticTexts["publicProfileName"].waitForExistence(timeout: 5))
        capture("compact-profile-large-text")
    }

    private func launch(state: String? = nil, extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-town-preview", "-appearance", "light", "-forest3DEnabled", "YES"] + extra
        if let state { app.launchArguments += ["-town-friends-preview-state", state] }
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
