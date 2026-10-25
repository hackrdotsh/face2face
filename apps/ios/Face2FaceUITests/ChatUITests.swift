import XCTest

@MainActor
final class ChatUITests: XCTestCase {
    func testBlockActionClosesConversationAndDisablesMessaging() {
        let app = launch()
        app.buttons["town-connections"].tap()
        XCTAssertTrue(app.buttons["chat-preview-private"].waitForExistence(timeout: 5))
        app.buttons["chat-preview-private"].tap()
        XCTAssertTrue(app.buttons["chatOptions"].waitForExistence(timeout: 5))
        app.buttons["chatOptions"].tap()
        app.buttons["Block connection"].tap()
        let confirm = app.sheets["Block this connection?"].buttons["chatConfirmBlock"].firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 3))
        confirm.tap()
        XCTAssertTrue(app.staticTexts["This table is closed"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["chatSend"].exists)
        capture("blocked-conversation")
    }
    func testPhotoPickerPreparesAndSendsASelectedPhoto() throws {
        let app = launch()
        app.buttons["town-connections"].tap()
        XCTAssertTrue(app.buttons["chat-preview-ava"].waitForExistence(timeout: 5))
        app.buttons["chat-preview-ava"].tap()
        let attach = app.buttons["chatAttachPhoto"]
        XCTAssertTrue(attach.waitForExistence(timeout: 5))
        attach.tap()
        let photo = app.descendants(matching: .any).matching(
            NSPredicate(format: "label BEGINSWITH 'Photo, '")
        ).firstMatch
        guard photo.waitForExistence(timeout: 8) else {
            print(app.debugDescription)
            throw XCTSkip(
                "Seed the simulator Photos library with an image using xcrun simctl addmedia before this test."
            )
        }
        photo.tap()
        if app.buttons["Add"].exists { app.buttons["Add"].tap() }
        XCTAssertTrue(app.staticTexts["Photo ready"].waitForExistence(timeout: 90))
        capture("chat-photo-ready")
        app.buttons["chatSend"].tap()
        XCTAssertTrue(app.images["Photo you sent in preview"].waitForExistence(timeout: 5))
        capture("chat-photo-sent")
    }
    func testCafeOpensPrivateConversationWithoutRevealingAProfileAndSendsText() {
        let app = launch()
        XCTAssertTrue(app.buttons["town-connections"].waitForExistence(timeout: 8))
        app.buttons["town-connections"].tap()
        let chat = app.buttons["chat-preview-private"]
        XCTAssertTrue(chat.waitForExistence(timeout: 5))
        capture("cafe-chat-list")
        chat.tap()
        XCTAssertTrue(app.staticTexts["chatTitle"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["chatTitle"].label, "Anonymous connection")
        let draft = app.descendants(matching: .any).matching(identifier: "chatDraft").firstMatch
        draft.tap()
        draft.typeText("See you at the cafe!")
        app.buttons["chatSend"].tap()
        XCTAssertTrue(app.staticTexts["See you at the cafe!"].waitForExistence(timeout: 5))
        capture("private-chat-sent")
        app.buttons["chatBack"].tap()
        XCTAssertTrue(chat.waitForExistence(timeout: 5))
    }
    func testPublicProfileMessageButtonOpensTheSameConversation() {
        let app = launch()
        let friend = app.buttons["town-friend-preview-ava"]
        XCTAssertTrue(friend.waitForExistence(timeout: 8))
        friend.tap()
        let message = app.buttons["publicProfileMessage"]
        XCTAssertTrue(message.waitForExistence(timeout: 5))
        for _ in 0..<4 {
            if message.isHittable { break }
            app.swipeUp()
        }
        message.tap()
        XCTAssertTrue(app.staticTexts["chatTitle"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["chatTitle"].label, "Ava")
        capture("profile-to-chat")
    }
    func testPrivateChatShowsTheirBlobThinking() {
        let app = launch(extra: ["-town-chat", "preview-private", "-chat-preview-typing"])
        XCTAssertTrue(app.staticTexts["chatTitle"].waitForExistence(timeout: 8))
        XCTAssertEqual(app.staticTexts["chatTitle"].label, "Anonymous connection")
        XCTAssertTrue(app.otherElements["chatTyping"].waitForExistence(timeout: 5))
        capture("private-chat-typing")
    }
    private func launch(extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-town-preview", "-appearance", "light"] + extra
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
