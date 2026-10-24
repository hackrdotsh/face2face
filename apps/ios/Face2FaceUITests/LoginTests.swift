import XCTest

@MainActor
final class LoginTests: XCTestCase {
    func testLoginExpandsIntoFormAndReturnsToWelcome() {
        let app = launchApp(openLogin: false)
        XCTAssertTrue(app.buttons["loginStart"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["loginStart"].label, "Login")
        XCTAssertFalse(app.textFields["emailField"].exists)
        XCTAssertFalse(app.staticTexts["Take the scenic route"].exists)
        capture("Welcome")

        app.buttons["loginStart"].tap()
        XCTAssertTrue(app.textFields["emailField"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["loginStart"].exists)
        capture("Expanded login")

        app.buttons["loginBack"].tap()
        XCTAssertTrue(app.buttons["loginStart"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.textFields["emailField"].exists)
    }

    func testAccountModesKeyboardAndConnectionSettings() {
        let app = launchApp()
        XCTAssertTrue(app.textFields["emailField"].waitForExistence(timeout: 5))
        capture("Sign in")

        XCTAssertFalse(app.buttons["sceneryToggle"].exists)

        reveal(app.buttons["accountModeToggle"], in: app)
        app.buttons["accountModeToggle"].tap()
        XCTAssertTrue(app.textFields["nameField"].exists)
        reveal(app.textFields["nameField"], in: app)
        capture("Create account")
        app.textFields["nameField"].tap()
        app.textFields["nameField"].typeText("Meadow Tester")
        nextKey(in: app).tap()
        app.textFields["emailField"].typeText("meadow@example.test")
        nextKey(in: app).tap()
        app.secureTextFields["passwordField"].typeText("test-password-123")
        XCTAssertTrue(app.buttons["accountSubmit"].exists)
        capture("Keyboard")
        app.toolbars.buttons["Done"].tap()

        reveal(app.buttons["accountModeToggle"], in: app)
        app.buttons["accountModeToggle"].tap()
        XCTAssertFalse(app.textFields["nameField"].exists)
        app.swipeDown()
        app.swipeDown()
        app.buttons["connectionSettings"].tap()
        XCTAssertTrue(app.navigationBars["Connection"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.textFields["API URL"].exists)
        capture("Connection")
        app.navigationBars.buttons["Done"].tap()
        XCTAssertTrue(app.buttons["connectionSettings"].exists)
    }

    func testLargeTextCanReachAccountControls() {
        let app = launchApp(largeText: true)
        let toggle = app.buttons["accountModeToggle"]
        reveal(toggle, in: app)
        XCTAssertTrue(toggle.isHittable)
        capture("Large text sign in")
        toggle.tap()
        reveal(app.buttons["accountSubmit"], in: app)
        XCTAssertTrue(app.buttons["accountSubmit"].isHittable)
        capture("Large text create account")
    }

    func testSignInErrorKeepsFormUsable() {
        let app = launchApp()
        reveal(app.buttons["accountSubmit"], in: app)
        app.buttons["accountSubmit"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["authError"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["accountSubmit"].isEnabled)
        XCTAssertTrue(app.buttons["accountModeToggle"].isEnabled)
        capture("Sign in error")
    }

    private func nextKey(in app: XCUIApplication) -> XCUIElement {
        app.keyboards.buttons.matching(
            NSPredicate(format: "label ==[c] 'next' OR identifier == 'Next:'")
        ).firstMatch
    }

    private func launchApp(largeText: Bool = false, openLogin: Bool = true) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        // An empty server avoids networking and existing Keychain sessions in layout tests.
        app.launchArguments = ["-apiAddress", ""]
        if largeText {
            app.launchArguments += [
                "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL",
            ]
        }
        app.launch()
        if openLogin {
            let login = app.buttons["loginStart"]
            XCTAssertTrue(login.waitForExistence(timeout: 5))
            reveal(login, in: app)
            login.tap()
            XCTAssertTrue(app.textFields["emailField"].waitForExistence(timeout: 5))
        }
        return app
    }

    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<6 {
            if element.isHittable { return }
            app.swipeUp()
        }
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
