import XCTest

@MainActor
final class FreshSignInUITests: XCTestCase {
    func testSignedOutLaunchOpensRealLoginEvenIfPreviewFlagWasLeftOn() {
        let app = XCUIApplication()
        app.launchArguments = ["-start-signed-out", "-town-preview", "-appearance", "light"]
        app.launch()
        XCTAssertTrue(app.buttons["loginStart"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.buttons["townAccount"].exists)
        app.buttons["loginStart"].tap()
        XCTAssertTrue(app.textFields["emailField"].waitForExistence(timeout: 5))
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = "fresh-real-login"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testPreviewCanReturnToRealSignInWithoutDeletingAnAccount() {
        let app = XCUIApplication()
        app.launchArguments = ["-town-preview", "-appearance", "light"]
        app.launch()
        XCTAssertTrue(app.buttons["appSettings"].waitForExistence(timeout: 8))
        app.buttons["appSettings"].tap()
        let exit = app.buttons["exitTownPreview"]
        for _ in 0..<6 {
            if exit.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(exit.isHittable)
        XCTAssertTrue(exit.isEnabled)
        exit.tap()
        XCTAssertTrue(app.buttons["loginStart"].waitForExistence(timeout: 5))
        app.buttons["loginStart"].tap()
        XCTAssertTrue(app.textFields["emailField"].waitForExistence(timeout: 5))
    }
}
