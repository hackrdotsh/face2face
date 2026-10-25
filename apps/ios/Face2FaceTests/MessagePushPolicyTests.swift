import UserNotifications
import XCTest

@testable import Face2Face

final class MessagePushPolicyTests: XCTestCase {
    func testMessagesOutsideTheVisibleChatGetBannerSoundAndBadge() {
        let policy = MessagePushVisibility()
        let options = policy.options(kind: "message", chatID: "public-friend", accountID: "viewer")
        XCTAssertTrue(options.contains(.banner))
        XCTAssertTrue(options.contains(.sound))
        XCTAssertTrue(options.contains(.badge))
        XCTAssertTrue(options.contains(.list))
        XCTAssertTrue(policy.options(kind: "connected", chatID: nil, accountID: "viewer").isEmpty)
    }

    func testOnlyTheCurrentAccountsVisibleConversationSuppressesMessageAlerts() {
        var policy = MessagePushVisibility()
        let owner = UUID()
        policy.show(chatID: "one", accountID: "viewer", owner: owner)
        XCTAssertTrue(policy.options(kind: "message", chatID: "one", accountID: "viewer").isEmpty)
        XCTAssertTrue(policy.options(kind: "message", chatID: "two", accountID: "viewer").contains(.banner))
        XCTAssertTrue(
            policy.options(kind: "message", chatID: "one", accountID: "other-account").contains(.banner))
        policy.hide(owner: owner)
        XCTAssertTrue(policy.options(kind: "message", chatID: "one", accountID: "viewer").contains(.banner))
    }

    func testOldViewDisappearanceCannotClearTheNewViewsVisibility() {
        var policy = MessagePushVisibility()
        let old = UUID()
        let current = UUID()
        policy.show(chatID: "one", accountID: "viewer", owner: old)
        policy.show(chatID: "two", accountID: "viewer", owner: current)
        policy.hide(owner: old)
        XCTAssertTrue(policy.options(kind: "message", chatID: "two", accountID: "viewer").isEmpty)
        policy.clear()
        XCTAssertTrue(policy.options(kind: "message", chatID: "two", accountID: "viewer").contains(.banner))
    }
}
