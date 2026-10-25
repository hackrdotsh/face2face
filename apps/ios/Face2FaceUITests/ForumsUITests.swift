import XCTest

@MainActor
final class ForumsUITests: XCTestCase {
    func testUpcomingEventRSVPAndAttendees() {
        let app = launch()
        let coffee = app.buttons["forum-post-preview-coffee"]
        XCTAssertTrue(coffee.waitForExistence(timeout: 8))
        capture("forums-board")
        coffee.tap()
        let rsvp = app.buttons["forumRSVP"]
        reveal(rsvp, in: app)
        XCTAssertTrue(rsvp.isHittable)
        rsvp.tap()
        waitForLabel(rsvp, contains: "Leave event")
        XCTAssertEqual(app.staticTexts["forumAttendeeCount"].label, "3 going")
        capture("forum-event-going")
        app.buttons["forumAttendees"].tap()
        XCTAssertTrue(app.staticTexts["Preview Walker"].waitForExistence(timeout: 5))
        capture("forum-attendees")
        app.buttons["Back to event"].tap()
        reveal(rsvp, in: app)
        rsvp.tap()
        waitForLabel(rsvp, contains: "I'll be there")
    }
    func testCreateEditAndCancelMyEvent() {
        let app = launch()
        app.buttons["forumCreate"].tap()
        let title = app.textFields["forumEventTitle"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        title.tap()
        title.typeText("Demo meetup")
        capture("forum-compose")
        app.buttons["forumEventSave"].tap()
        let created = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH 'forum-post-' AND label CONTAINS 'Demo meetup'")
        ).firstMatch
        XCTAssertTrue(created.waitForExistence(timeout: 5))
        reveal(created, in: app)
        created.tap()
        XCTAssertTrue(app.buttons["forumEventOptions"].waitForExistence(timeout: 5))
        app.buttons["forumEventOptions"].tap()
        app.buttons["Edit event"].tap()
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        title.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
        // Focusing an existing field may select its last word on newer iOS versions.
        title.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: "Demo meetup".count))
        title.typeText("Demo meetup updated")
        XCTAssertEqual(title.value as? String, "Demo meetup updated")
        app.buttons["forumEventSave"].tap()
        let heading = app.staticTexts["forumEventHeading"]
        XCTAssertTrue(heading.waitForExistence(timeout: 5))
        waitForLabel(heading, contains: "Demo meetup updated")
        app.buttons["forumEventOptions"].tap()
        app.buttons["Cancel event"].tap()
        let confirm = app.sheets["Cancel this event?"].buttons["forumConfirmCancel"].firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 3))
        confirm.tap()
        XCTAssertTrue(app.staticTexts["forumEventStatus"].waitForExistence(timeout: 5))
        waitForLabel(app.staticTexts["forumEventStatus"], contains: "Cancelled")
        XCTAssertFalse(app.buttons["forumEventOptions"].exists)
        capture("forum-event-cancelled")
    }
    func testFreshInterestSelectionUnlocksForums() {
        let app = launch(state: "empty")
        XCTAssertTrue(app.staticTexts["Find your kind of people"].waitForExistence(timeout: 5))
        app.buttons["forumInterests"].tap()
        let coffee = app.buttons["coffee"]
        XCTAssertTrue(coffee.waitForExistence(timeout: 5))
        reveal(coffee, in: app)
        coffee.tap()
        let selected = expectation(for: NSPredicate(format: "selected == true"), evaluatedWith: coffee)
        wait(for: [selected], timeout: 5)
        capture("forum-interest-selection")
        app.buttons["forumInterestsDone"].tap()
        XCTAssertTrue(app.buttons["forum-post-preview-coffee"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["forumCreate"].isEnabled)
    }

    func testNewInterestWithoutThreeMembersShowsWaitingState() {
        let app = launch(state: "waiting")
        XCTAssertTrue(app.staticTexts["Your circles are growing"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["forumCreate"].isEnabled)
        XCTAssertFalse(app.buttons["forum-post-preview-coffee"].exists)
        capture("forums-waiting-for-members")
    }
    func testCanLeavePastEventButCannotJoinAgain() {
        let app = launch()
        app.segmentedControls["forumTabs"].buttons["Your forums"].tap()
        app.buttons["forum-coffee"].tap()
        let past = app.buttons["forum-post-preview-past"]
        XCTAssertTrue(past.waitForExistence(timeout: 5))
        reveal(past, in: app)
        past.tap()
        let rsvp = app.buttons["forumRSVP"]
        reveal(rsvp, in: app)
        XCTAssertTrue(rsvp.isEnabled)
        rsvp.tap()
        waitForLabel(rsvp, contains: "Event finished")
        XCTAssertFalse(rsvp.isEnabled)
    }
    func testLargeTextAndErrorStates() {
        let large = launch(extra: [
            "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL",
        ])
        let event = large.buttons["forum-post-preview-coffee"]
        reveal(event, in: large)
        XCTAssertTrue(event.isHittable)
        event.tap()
        let rsvp = large.buttons["forumRSVP"]
        reveal(rsvp, in: large)
        XCTAssertTrue(rsvp.isHittable)
        capture("forum-event-large-text")
        large.terminate()
        let error = launch(state: "error")
        XCTAssertTrue(error.staticTexts["Couldn't open the board"].waitForExistence(timeout: 5))
        XCTAssertTrue(error.buttons["Try again"].exists)
        XCTAssertFalse(error.staticTexts["Find your kind of people"].exists)
    }
    private func launch(state: String? = nil, extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments =
            ["-town-preview", "-town-destination", "forums", "-appearance", "light"] + extra
        if let state { app.launchArguments += ["-forums-preview-state", state] }
        app.launch()
        XCTAssertTrue(app.staticTexts["forumsPreviewLabel"].waitForExistence(timeout: 8))
        return app
    }
    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<8 {
            if element.isHittable { return }
            app.swipeUp()
        }
    }
    private func waitForLabel(_ element: XCUIElement, contains text: String) {
        let expectation = expectation(
            for: NSPredicate(format: "label CONTAINS %@", text), evaluatedWith: element)
        wait(for: [expectation], timeout: 5)
    }
    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
