import XCTest

@MainActor
final class TownUITests: XCTestCase {
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
            XCTAssertTrue(app.staticTexts["Town preview"].waitForExistence(timeout: 4))
            capture(identifiers[index])
            app.buttons["Done"].tap()
            XCTAssertTrue(button.waitForExistence(timeout: 4))
        }
        app.buttons["townAccount"].tap()
        XCTAssertTrue(app.otherElements["accountHome"].waitForExistence(timeout: 4))
        app.buttons["Done"].tap()
        XCTAssertTrue(app.buttons["town-forums"].waitForExistence(timeout: 4))
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
        XCTAssertTrue(app.staticTexts["Town preview"].waitForExistence(timeout: 4))
        capture("large-text-destination")
    }

    private func launch(extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-town-preview", "-appearance", "light"] + extra
        app.launch()
        return app
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = "town-\(name)"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
