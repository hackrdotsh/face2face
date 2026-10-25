import XCTest

@MainActor
final class CampfireUITests: XCTestCase {
    func testCampfireWidgetGalleryRendersArtwork() {
        _ = launch()
        XCUIDevice.shared.press(.home)
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        XCTAssertTrue(springboard.wait(for: .runningForeground, timeout: 5))
        let icon = springboard.icons["face2face"].firstMatch
        XCTAssertTrue(icon.waitForExistence(timeout: 5))
        icon.press(forDuration: 1.2)
        let editHome = springboard.buttons["Edit Home Screen"]
        guard editHome.waitForExistence(timeout: 5) else {
            XCTFail("Missing Home Screen edit menu: \(springboard.debugDescription)")
            return
        }
        editHome.tap()
        let edit = springboard.buttons["Edit"]
        XCTAssertTrue(edit.waitForExistence(timeout: 5))
        edit.tap()
        let add = springboard.buttons["Add Widget"]
        guard add.waitForExistence(timeout: 5) else {
            XCTFail("Missing widget gallery menu: \(springboard.debugDescription)")
            return
        }
        add.tap()
        let search = springboard.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        search.typeText("face2face")
        let row = springboard.staticTexts["face2face"].firstMatch
        guard row.waitForExistence(timeout: 8) else {
            XCTFail("Campfire extension missing from gallery: \(springboard.debugDescription)")
            return
        }
        row.tap()
        XCTAssertTrue(springboard.staticTexts["Around the campfire"].waitForExistence(timeout: 8))
        capture("campfire-widget-gallery")
        XCUIDevice.shared.press(.home)
        if springboard.buttons["Done"].exists { springboard.buttons["Done"].tap() }
    }

    func testProfileIsBlobOnlyAndCanReact() {
        let app = launch()
        app.buttons["townAccount"].tap()
        let blob = app.buttons["profileBlob"]
        XCTAssertTrue(blob.waitForExistence(timeout: 5))
        XCTAssertTrue(blob.isEnabled)
        blob.tap()
        XCTAssertFalse(app.buttons["Choose a Photo"].exists)
        XCTAssertFalse(app.buttons["Change Photo"].exists)
        XCTAssertFalse(app.buttons["Remove Photo"].exists)
        capture("blob-only-profile")
    }

    func testCampfireOpensWithSampleFriendsAndWidgetLinkDismissesIt() {
        let app = launch()
        app.buttons["townCampfire"].tap()
        XCTAssertTrue(app.staticTexts["campfirePreviewLabel"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Ava"].waitForExistence(timeout: 5))
        capture("friends-around-the-fire")
        app.open(URL(string: "face2face://connections")!)
        XCTAssertTrue(app.staticTexts["chatsPreviewLabel"].waitForExistence(timeout: 8))
    }

    func testLargeTextCampfireAndSharingConsentAreReachable() {
        let app = launch(extra: [
            "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL",
        ])
        app.buttons["townCampfire"].tap()
        XCTAssertTrue(app.staticTexts["campfirePreviewLabel"].waitForExistence(timeout: 5))
        capture("campfire-large-text")
        app.navigationBars.buttons["Done"].tap()
        app.buttons["appSettings"].tap()
        let toggle = app.switches["campfireWidgetToggle"]
        for _ in 0..<12 {
            if toggle.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(toggle.isHittable)
        XCTAssertFalse(toggle.isEnabled, "Offline preview must never publish sample friend data")
        capture("campfire-widget-consent")
    }

    private func launch(extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-town-preview", "-appearance", "light"] + extra
        app.launch()
        XCTAssertTrue(app.buttons["townCampfire"].waitForExistence(timeout: 8))
        return app
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
