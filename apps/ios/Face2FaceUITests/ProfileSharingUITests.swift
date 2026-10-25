import XCTest

@MainActor
final class ProfileSharingUITests: XCTestCase {
    func testCancelThenAgreeWaitsAnonymouslyAndStillSendsMessages() {
        let app = launch()
        let share = app.buttons["chatShareProfiles"]
        XCTAssertTrue(share.waitForExistence(timeout: 8))
        share.tap()
        let alert = app.alerts["Share profiles with this connection?"]
        XCTAssertTrue(alert.waitForExistence(timeout: 3))
        capture("sharing-confirmation")
        alert.buttons["Keep anonymous"].tap()
        XCTAssertTrue(share.exists)
        XCTAssertFalse(app.staticTexts["chatSharingWaiting"].exists)
        share.tap()
        alert.buttons["Agree to share"].tap()
        XCTAssertTrue(app.staticTexts["chatSharingWaiting"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["connectionCelebrationDismiss"].exists)
        XCTAssertFalse(share.exists)
        XCTAssertFalse(app.buttons["chatViewProfile"].exists)
        XCTAssertEqual(app.staticTexts["chatTitle"].label, "Anonymous connection")
        capture("sharing-waiting")
        let draft = app.descendants(matching: .any).matching(identifier: "chatDraft").firstMatch
        draft.tap()
        draft.typeText("We can still chat")
        app.buttons["chatSend"].tap()
        XCTAssertTrue(app.staticTexts["We can still chat"].waitForExistence(timeout: 5))
        app.buttons["chatBack"].tap()
        XCTAssertFalse(app.buttons["town-friend-preview-private"].exists)
    }

    func testMutualAgreementOpensProfileAndAddsTownVisitor() {
        let app = launch(mode: "peer-agreed")
        XCTAssertTrue(app.buttons["chatShareProfiles"].waitForExistence(timeout: 8))
        app.buttons["chatShareProfiles"].tap()
        app.alerts.buttons["Agree to share"].tap()
        dismissCelebration(app)
        XCTAssertTrue(app.staticTexts["chatProfilesPublic"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["chatTitle"].label, "Rowan")
        capture("sharing-public-chat")
        app.buttons["chatViewProfile"].tap()
        XCTAssertTrue(app.staticTexts["publicProfileName"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["publicProfileName"].label, "Rowan, 27")
        capture("sharing-public-profile")
        app.buttons["publicProfileClose"].tap()
        app.buttons["chatBack"].tap()
        XCTAssertTrue(app.buttons["town-friend-preview-private"].waitForExistence(timeout: 8))
        capture("sharing-new-town-visitor")
        app.buttons["town-friend-preview-private"].tap()
        XCTAssertTrue(app.staticTexts["publicProfileName"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["publicProfileName"].label, "Rowan, 27")
    }

    func testPeerAgreesWhileChatRemainsOpen() {
        let app = launch(mode: "peer-later")
        XCTAssertTrue(app.buttons["chatShareProfiles"].waitForExistence(timeout: 8))
        app.buttons["chatShareProfiles"].tap()
        app.alerts.buttons["Agree to share"].tap()
        XCTAssertTrue(app.staticTexts["chatSharingWaiting"].waitForExistence(timeout: 3))
        dismissCelebration(app)
        XCTAssertTrue(app.staticTexts["chatProfilesPublic"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["chatTitle"].label, "Rowan")
        XCTAssertTrue(app.buttons["chatViewProfile"].exists)
    }

    private func launch(mode: String? = nil) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-town-preview", "-town-chat", "preview-private", "-appearance", "light"]
        if let mode { app.launchArguments += ["-chat-sharing-preview-state", mode] }
        app.launch()
        return app
    }

    private func dismissCelebration(_ app: XCUIApplication) {
        XCTAssertTrue(app.buttons["connectionCelebrationDismiss"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.staticTexts["connectionCelebrationTitle"].label, "A familiar face!")
        capture("public-connection-celebration")
        app.buttons["connectionCelebrationDismiss"].tap()
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
