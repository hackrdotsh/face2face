import Face2FaceCore
import XCTest

@testable import Face2Face

@MainActor
final class ForumsModelTests: XCTestCase {
    func testSelectedNewInterestWaitsForItsForumToOpen() async throws {
        let repository = PreviewForumRepository(state: "waiting")
        let model = ForumsModel(context: ForumContext(repository: repository))
        await model.reload()
        XCTAssertTrue(model.forums.isEmpty)
        XCTAssertEqual(model.pendingInterests.map(\.name), ["kite flying"])
        XCTAssertNil(model.error)
    }
    func testInterestChoicesEnforceTheServerMaximumAndOpenForums() async throws {
        let repository = PreviewForumRepository(state: "empty")
        let context = ForumContext(repository: repository)
        let session = SessionModel()
        session.enterTownPreview()
        let interests = InterestsModel(session: session, repository: { try await context.repository() })
        await interests.load()
        let initial = try XCTUnwrap(interests.catalog)
        XCTAssertTrue(initial.selected.isEmpty)
        for choice in initial.interests.prefix(10) { interests.toggle(choice) }
        XCTAssertEqual(interests.catalog?.selected.count, 10)
        let extra = try XCTUnwrap(initial.interests.last)
        interests.toggle(extra)
        XCTAssertEqual(interests.catalog?.selected.count, 10)
        XCTAssertNotNil(interests.errorMessage)
        for _ in 0..<100 {
            if try await repository.interests().selected.count == 10 { break }
            await Task.yield()
        }
        let forums = try await repository.townForums()
        XCTAssertEqual(forums.count, 10)
    }
    func testPagedUpcomingFeedAppendsWithoutDuplicateIDs() async throws {
        let repository = PreviewForumRepository()
        _ = try await repository.replaceInterests(["coffee", "music", "art"])
        let model = ForumFeedModel(context: ForumContext(repository: repository), forumID: nil)
        await model.reload()
        XCTAssertEqual(model.posts.count, 2)
        XCTAssertTrue(model.hasMore)
        await model.loadMore()
        XCTAssertEqual(model.posts.count, 3)
        XCTAssertEqual(Set(model.posts.map(\.id)).count, 3)
        XCTAssertFalse(model.hasMore)
        await model.loadMore()
        XCTAssertEqual(model.posts.count, 3)
    }
    func testCanLeaveCancelledEventButCannotRejoin() async throws {
        let repository = PreviewForumRepository()
        let model = ForumPostModel(context: ForumContext(repository: repository), id: "preview-event")
        await model.reload()
        await model.rsvp()
        XCTAssertTrue(model.post?.attending == true)
        await model.cancel()
        XCTAssertTrue(model.post?.cancelled == true)
        await model.rsvp()
        XCTAssertTrue(model.post?.attending == false)
        await model.rsvp()
        XCTAssertTrue(model.post?.attending == false)
        XCTAssertNotNil(model.error)
    }
    func testMembershipLossClearsPreviouslyVisiblePostAndFeed() async throws {
        let repository = PreviewForumRepository()
        let context = ForumContext(repository: repository)
        let post = ForumPostModel(context: context, id: "preview-coffee")
        let feed = ForumFeedModel(context: context, forumID: "coffee")
        await post.reload()
        await feed.reload()
        XCTAssertNotNil(post.post)
        XCTAssertFalse(feed.posts.isEmpty)
        _ = try await repository.replaceInterests([])
        await post.reload()
        await feed.reload()
        XCTAssertNil(post.post)
        XCTAssertTrue(feed.posts.isEmpty)
        XCTAssertNotNil(post.error)
        XCTAssertNotNil(feed.error)
    }
}
