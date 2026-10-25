import XCTest

@MainActor
final class TownUITests: XCTestCase {
    func testTwoDimensionalTownRemainsAvailable() {
        let app = launch(scenery3D: false)
        let forums = app.buttons["town-forums"]
        XCTAssertTrue(forums.waitForExistence(timeout: 8))
        forums.tap()
        XCTAssertTrue(app.staticTexts["Town preview"].waitForExistence(timeout: 4))
        app.buttons["Done"].tap()
        XCTAssertTrue(app.buttons["townAccount"].waitForExistence(timeout: 4))
    }

    func testBuildingsOpenAndDismissTheirOwnDestinations() {
        let app = launch()
        let identifiers = ["encounters", "connections", "forums"]
        let buttons = identifiers.map { app.buttons["town-\($0)"] }
        XCTAssertTrue(buttons[0].waitForExistence(timeout: 8))
        for button in buttons {
            XCTAssertTrue(button.isHittable)
            XCTAssertGreaterThanOrEqual(button.frame.width, 44)
            XCTAssertGreaterThanOrEqual(button.frame.height, 44)
        }
        for (index, button) in buttons.enumerated() {
            for other in buttons.dropFirst(index + 1) {
                XCTAssertFalse(button.frame.intersects(other.frame), "Building hit areas must not overlap")
            }
            button.tap()
            if identifiers[index] == "connections" {
                XCTAssertTrue(app.staticTexts["chatsPreviewLabel"].waitForExistence(timeout: 4))
            } else if identifiers[index] == "forums" {
                XCTAssertTrue(app.staticTexts["forumsPreviewLabel"].waitForExistence(timeout: 4))
            } else {
                XCTAssertTrue(app.staticTexts["encountersPreviewLabel"].waitForExistence(timeout: 4))
            }
            capture(identifiers[index])
            if identifiers[index] == "encounters" {
                app.buttons["encountersBack"].tap()
            } else if identifiers[index] == "forums" {
                app.buttons["Back to town"].tap()
            } else {
                app.buttons["Done"].tap()
            }
            XCTAssertTrue(button.waitForExistence(timeout: 4))
        }
    }

    func testHeaderKeepsAccountAndSettingsSeparateWithoutTabs() {
        let app = launch()
        let settings = app.buttons["appSettings"]
        let account = app.buttons["townAccount"]
        XCTAssertTrue(settings.waitForExistence(timeout: 8))
        XCTAssertFalse(app.staticTexts["FACE2FACE"].exists)
        XCTAssertTrue(account.exists)
        XCTAssertLessThan(settings.frame.maxX, account.frame.minX)
        XCTAssertEqual(settings.frame.midY, account.frame.midY, accuracy: 4)
        XCTAssertTrue(app.tabBars.allElementsBoundByIndex.isEmpty)
        account.tap()
        XCTAssertTrue(app.otherElements["accountHome"].waitForExistence(timeout: 4))
        XCTAssertTrue(app.staticTexts["Hey, Preview Walker."].exists)
        let search = app.textFields["interestSearch"]
        XCTAssertTrue(search.waitForExistence(timeout: 4))
        XCTAssertTrue(app.buttons["coffee"].exists, "Picked interests show as pills")
        XCTAssertLessThan(search.frame.minY, app.switches["discoveryToggle"].frame.minY)
        XCTAssertLessThan(
            app.buttons["homeSignOut"].frame.maxY, search.frame.minY, "Sign Out stays with the profile")
        capture("account-top")
        XCTAssertTrue(app.buttons["homeSignOut"].exists)
        XCTAssertTrue(app.buttons["addPasskey"].exists)
        reveal(app.buttons["addPasskey"], in: app)
        XCTAssertTrue(app.buttons["addPasskey"].isHittable)
        XCTAssertFalse(app.buttons["addPasskey"].isEnabled)
        XCTAssertTrue(app.switches["discoveryToggle"].exists)
        XCTAssertFalse(app.switches["discoveryToggle"].isEnabled)
        capture("account")
        app.navigationBars["Account"].buttons["Done"].tap()
        XCTAssertTrue(settings.waitForExistence(timeout: 4))
        settings.tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 4))
        XCTAssertFalse(app.buttons["homeSignOut"].exists)
        XCTAssertFalse(app.buttons["addPasskey"].exists)
        XCTAssertFalse(app.switches["discoveryToggle"].exists)
        XCTAssertFalse(app.otherElements["accountHome"].exists)
        capture("settings-discovery")

        reveal(app.segmentedControls["appearancePicker"], in: app)
        XCTAssertTrue(app.segmentedControls["appearancePicker"].isHittable)
        reveal(app.textFields["API URL"], in: app)
        XCTAssertTrue(app.textFields["API URL"].isHittable)
        reveal(app.buttons["Device test"], in: app)
        for label in ["Walk test", "Connected test", "Pocket test", "Device test"] {
            XCTAssertTrue(app.buttons[label].exists)
        }
        capture("settings-preferences")
        app.navigationBars["Settings"].buttons["Done"].tap()
        XCTAssertTrue(app.buttons["town-forums"].waitForExistence(timeout: 4))
        XCTAssertTrue(app.tabBars.allElementsBoundByIndex.isEmpty)
    }

    func testLargeTextCanReachSettingsAndReturnToTown() {
        let app = launch(extra: [
            "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL",
        ])
        let settings = app.buttons["appSettings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 8))
        app.buttons["townAccount"].tap()
        XCTAssertTrue(app.otherElements["accountHome"].waitForExistence(timeout: 4))
        reveal(app.switches["discoveryToggle"], in: app)
        XCTAssertTrue(app.switches["discoveryToggle"].isHittable)
        reveal(app.buttons["addPasskey"], in: app)
        XCTAssertTrue(app.buttons["addPasskey"].isHittable)
        capture("account-passkey-large-text")
        app.navigationBars["Account"].buttons["Done"].tap()
        settings.tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 4))
        reveal(app.segmentedControls["appearancePicker"], in: app)
        XCTAssertTrue(app.segmentedControls["appearancePicker"].isHittable)
        capture("settings-large-text")
        app.navigationBars["Settings"].buttons["Done"].tap()
        XCTAssertTrue(settings.waitForExistence(timeout: 4))
    }

    func testDiscoveryToggleIsOffAndDisabledWithoutBluetooth() {
        let app = launch()
        let toggle = app.descendants(matching: .any)["townDiscovery"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 8))
        XCTAssertEqual(toggle.label, "Discovery")
        XCTAssertEqual(toggle.value as? String, "Off")
        XCTAssertFalse(toggle.isEnabled)
        XCTAssertEqual(toggle.frame.width, 44, accuracy: 1)
        XCTAssertEqual(toggle.frame.height, 44, accuracy: 1)
        XCTAssertFalse(toggle.frame.intersects(app.buttons["townNotifications"].frame))
        capture("discovery-toggle")
    }

    func testAccessibilityTextUsesFullSizeNavigation() {
        let app = launch(extra: [
            "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL",
        ])
        let forums = app.buttons["town-forums"]
        XCTAssertTrue(forums.waitForExistence(timeout: 8))
        app.swipeUp()
        XCTAssertTrue(forums.isHittable)
        forums.tap()
        XCTAssertTrue(app.staticTexts["forumsPreviewLabel"].waitForExistence(timeout: 4))
        capture("large-text-destination")
    }

    private func launch(extra: [String] = [], scenery3D: Bool = true) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments =
            ["-town-preview", "-appearance", "light", "-forest3DEnabled", scenery3D ? "YES" : "NO"] + extra
        app.launch()
        return app
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = "town-\(name)"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<10 {
            if element.isHittable { return }
            app.swipeUp()
        }
    }
}
