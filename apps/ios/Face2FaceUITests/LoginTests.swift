import XCTest

@MainActor
final class LoginTests: XCTestCase {
    func testAppearanceSwitchingAndPersistence() {
        let app = launchApp(openLogin: false, appearance: nil)
        app.buttons["appSettings"].tap()
        let themes = app.segmentedControls["appearancePicker"]
        XCTAssertTrue(themes.waitForExistence(timeout: 3))
        themes.buttons["Dark"].tap()
        XCTAssertTrue(themes.buttons["Dark"].isSelected)
        capture("Dark settings")
        app.navigationBars.buttons["Done"].tap()
        capture("Dark welcome")

        app.terminate()
        app.launch()
        app.buttons["appSettings"].tap()
        XCTAssertTrue(themes.buttons["Dark"].isSelected)
        app.navigationBars.buttons["Done"].tap()
        app.buttons["loginStart"].tap()
        XCTAssertTrue(app.textFields["emailField"].waitForExistence(timeout: 5))
        capture("Dark login form")
        app.buttons["loginBack"].tap()
        app.buttons["appSettings"].tap()
        themes.buttons["Light"].tap()
        XCTAssertTrue(themes.buttons["Light"].isSelected)
        app.navigationBars.buttons["Done"].tap()
        capture("Light welcome")

        app.buttons["appSettings"].tap()
        themes.buttons["System"].tap()
        XCTAssertTrue(themes.buttons["System"].isSelected)
        app.navigationBars.buttons["Done"].tap()
    }

    func testRegistrationClosesAndReopensAsSignIn() {
        let app = launchApp()
        openCreateAccount(in: app)
        XCTAssertTrue(app.secureTextFields["passwordField"].exists)
        app.swipeDown()
        app.buttons["loginBack"].tap()
        XCTAssertTrue(app.buttons["loginStart"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.secureTextFields["passwordField"].exists)
        app.buttons["loginStart"].tap()
        XCTAssertTrue(app.textFields["emailField"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Email Code"].isSelected)
    }

    func testLoginPillEdgesAreTappable() {
        let app = launchApp(openLogin: false)
        let edges = [
            CGVector(dx: 0.08, dy: 0.5),
            CGVector(dx: 0.92, dy: 0.5),
            CGVector(dx: 0.5, dy: 0.12),
        ]
        for edge in edges {
            app.buttons["loginStart"].coordinate(withNormalizedOffset: edge).tap()
            XCTAssertTrue(app.textFields["emailField"].waitForExistence(timeout: 5))
            app.buttons["loginBack"].tap()
            XCTAssertTrue(app.buttons["loginStart"].waitForExistence(timeout: 5))
        }
    }

    func testGreetingAnimationKeepsWelcomeInteractive() {
        let app = launchApp(openLogin: false)
        capture("Approaching walker")
        let crossing = expectation(description: "First decorative crossing")
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.2) { crossing.fulfill() }
        wait(for: [crossing], timeout: 6)
        capture("Walking greeting")
        XCTAssertTrue(app.buttons["loginStart"].isHittable)
        app.buttons["loginStart"].tap()
        XCTAssertTrue(app.textFields["emailField"].waitForExistence(timeout: 5))
    }

    func testLoginExpandsIntoFormAndReturnsToWelcome() {
        let app = launchApp(openLogin: false)
        XCTAssertTrue(app.buttons["loginStart"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["loginStart"].label, "Get Started")
        XCTAssertLessThan(app.buttons["loginStart"].frame.width, app.frame.width * 0.7)
        XCTAssertGreaterThanOrEqual(app.buttons["loginStart"].frame.height, 44)
        XCTAssertEqual(app.buttons["loginStart"].frame.midY, app.frame.midY, accuracy: 4)
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

        app.buttons["loginStart"].tap()
        XCTAssertTrue(app.textFields["emailField"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.textFields["emailField"].isHittable)
        selectMethod("Password", in: app)
        XCTAssertTrue(app.secureTextFields["passwordField"].isHittable)
        reveal(app.buttons["accountSubmit"], in: app)
        XCTAssertTrue(app.buttons["accountSubmit"].isHittable)
    }

    func testAccountModesKeyboardAndSettings() {
        let app = launchApp()
        XCTAssertTrue(app.textFields["emailField"].waitForExistence(timeout: 5))
        capture("Sign in")

        XCTAssertFalse(app.buttons["sceneryToggle"].exists)

        openCreateAccount(in: app)
        XCTAssertTrue(app.secureTextFields["passwordField"].exists)
        reveal(app.textFields["emailField"], in: app)
        capture("Create account")
        app.textFields["emailField"].tap()
        app.textFields["emailField"].typeText("meadow@example.test")
        nextKey(in: app).tap()
        app.secureTextFields["passwordField"].typeText("test-password-123")
        XCTAssertTrue(app.buttons["accountSubmit"].exists)
        capture("Keyboard")
        app.toolbars.buttons["Done"].tap()

        app.buttons["signInLink"].tap()
        selectMethod("Password", in: app)
        XCTAssertTrue(app.buttons["Forgot Password?"].exists)
        XCTAssertTrue(app.buttons["Sign In with a Passkey"].exists)
        app.swipeDown()
        app.swipeDown()
        app.buttons["appSettings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.textFields["API URL"].exists)
        capture("Settings")
        app.navigationBars.buttons["Done"].tap()
        XCTAssertTrue(app.buttons["appSettings"].exists)
    }

    func testLargeTextCanReachAccountControls() {
        let app = launchApp(largeText: true)
        reveal(app.buttons["accountSubmit"], in: app)
        XCTAssertTrue(app.buttons["accountSubmit"].isHittable)
        capture("Large text sign in")
        openCreateAccount(in: app)
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
        XCTAssertTrue(app.buttons["Password"].isEnabled)
        capture("Sign in error")
    }

    private func nextKey(in app: XCUIApplication) -> XCUIElement {
        app.keyboards.buttons.matching(
            NSPredicate(format: "label ==[c] 'next' OR identifier == 'Next:'")
        ).firstMatch
    }

    private func openCreateAccount(in app: XCUIApplication) {
        let link = app.buttons["createAccountLink"]
        reveal(link, in: app)
        link.tap()
        XCTAssertTrue(app.secureTextFields["passwordField"].waitForExistence(timeout: 3))
    }

    private func selectMethod(_ title: String, in app: XCUIApplication) {
        let method = app.buttons[title]
        for _ in 0..<6 {
            if method.isHittable { break }
            app.swipeDown()
        }
        method.tap()
    }

    private func launchApp(
        largeText: Bool = false, openLogin: Bool = true, appearance: String? = "light"
    ) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        // An empty server avoids networking and existing Keychain sessions in layout tests.
        app.launchArguments = ["-apiAddress", ""]
        if let appearance { app.launchArguments += ["-appearance", appearance] }
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
