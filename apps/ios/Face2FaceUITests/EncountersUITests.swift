import XCTest

@MainActor
final class EncountersUITests: XCTestCase {
    func testAnonymousAcceptLeadsToMessagingOnlyAfterMutualYes() {
        let app = launch()
        XCTAssertFalse(app.staticTexts["Must stay hidden"].exists)
        let accept = app.buttons["accept-preview-chance"]
        reveal(accept, in: app)
        XCTAssertTrue(accept.isHittable)
        XCTAssertGreaterThanOrEqual(accept.frame.height, 44)
        capture("encounters-cards")
        accept.tap()
        let celebration = app.buttons["connectionCelebrationDismiss"]
        XCTAssertTrue(celebration.waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["connectionCelebrationTitle"].label, "You both said hello!")
        XCTAssertFalse(app.staticTexts["Must stay hidden"].exists)
        capture("private-connection-celebration")
        celebration.tap()
        let open = app.buttons["encounterOpenChat"]
        XCTAssertTrue(open.waitForExistence(timeout: 5))
        reveal(open, in: app)
        capture("encounter-mutual-accept")
        open.tap()
        XCTAssertTrue(app.staticTexts["chatTitle"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["chatTitle"].label, "Anonymous connection")
        let draft = app.descendants(matching: .any).matching(identifier: "chatDraft").firstMatch
        draft.tap()
        draft.typeText("Hello from our new connection!")
        app.buttons["chatSend"].tap()
        XCTAssertTrue(app.staticTexts["Hello from our new connection!"].waitForExistence(timeout: 5))
        capture("encounter-to-first-message")
    }
    func testDeclineRequiresConfirmationAndRemovesTheChance() {
        let app = launch()
        let decline = app.buttons["decline-preview-decline"]
        reveal(decline, in: app)
        decline.tap()
        let sheet = app.alerts["Let this chance pass?"]
        XCTAssertTrue(sheet.waitForExistence(timeout: 3))
        sheet.buttons["Keep chance"].tap()
        XCTAssertTrue(decline.exists)
        decline.tap()
        sheet.buttons["Decline chance"].tap()
        let gone = expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: decline)
        wait(for: [gone], timeout: 5)
        XCTAssertFalse(app.buttons["encounterOpenChat"].exists)
        capture("encounter-declined")
    }
    func testWaitingCardHasNoRepeatAnswerButtonsAndBlockWorks() {
        let app = launch()
        let waiting = app.staticTexts["chance-preview-waiting"]
        reveal(waiting, in: app)
        XCTAssertTrue(waiting.exists)
        XCTAssertFalse(app.buttons["accept-preview-waiting"].exists)
        XCTAssertFalse(app.buttons["decline-preview-waiting"].exists)
        let options = app.buttons["chanceOptions-preview-waiting"]
        reveal(options, in: app)
        options.tap()
        app.buttons["Block connection"].tap()
        let confirm = app.alerts["Block this connection?"].buttons["Block connection"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 3))
        confirm.tap()
        let gone = expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: waiting)
        wait(for: [gone], timeout: 5)
    }
    func testEmptyErrorAndLargeTextStates() {
        let empty = launch(state: "empty")
        XCTAssertTrue(empty.staticTexts["encountersEmpty"].waitForExistence(timeout: 5))
        empty.terminate()
        let failed = launch(state: "error")
        XCTAssertTrue(failed.staticTexts["encountersError"].waitForExistence(timeout: 5))
        XCTAssertFalse(failed.staticTexts["encountersEmpty"].exists)
        failed.terminate()
        let large = launch(extra: [
            "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL",
        ])
        let accept = large.buttons["accept-preview-chance"]
        reveal(accept, in: large)
        XCTAssertTrue(accept.isHittable)
        capture("encounters-large-text")
    }
    private func launch(state: String? = nil, extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments =
            ["-town-preview", "-town-destination", "encounters", "-appearance", "light"] + extra
        if let state { app.launchArguments += ["-encounters-preview-state", state] }
        app.launch()
        XCTAssertTrue(app.staticTexts["encountersPreviewLabel"].waitForExistence(timeout: 8))
        return app
    }
    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<10 {
            if element.isHittable { return }
            app.swipeUp()
        }
        for _ in 0..<10 {
            if element.isHittable { return }
            app.swipeDown()
        }
    }
    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
