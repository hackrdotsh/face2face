import Face2FaceCore
import Foundation
import Observation

@MainActor
@Observable
final class ForumContext {
    let isPreview: Bool
    private let session: SessionModel?
    private var fixedSource: (any ForumRepository)?
    private var pinnedClient: APIClient?
    var revision = 0

    init(session: SessionModel) {
        self.session = session
        isPreview = session.isTownPreview
        #if DEBUG
            if isPreview { fixedSource = PreviewForumRepository() }
        #endif
    }
    init(repository: any ForumRepository) {
        session = nil
        isPreview = false
        fixedSource = repository
    }
    func repository() async throws -> any ForumRepository {
        if let fixedSource {
            guard !isPreview || session?.isTownPreview == true else { throw APIError.unauthenticated }
            return fixedSource
        }
        guard let session else { throw APIError.unauthenticated }
        let current = try session.client()
        if let pinnedClient {
            guard try await current.usesSameCredential(as: pinnedClient) else {
                throw APIError.unauthenticated
            }
            return pinnedClient
        }
        let client = try await current.capturingCurrentCredential()
        pinnedClient = client
        return client
    }
    static func message(_ error: any Error) -> String {
        if let error = error as? APIError {
            switch error {
            case .server(404):
                return
                    "This forum or event isn't available. Check that its interest is still on your profile."
            case .server(413): return "This post is too large. Try a shorter description."
            case .invalidFields(let fields): return fields.values.sorted().joined(separator: " ")
            default: return error.localizedDescription
            }
        }
        return "Couldn't reach the notice board. Check your connection and try again."
    }
}

@MainActor
@Observable
final class ForumsModel {
    let context: ForumContext
    private(set) var forums: [TownForum] = []
    private(set) var pendingInterests: [InterestChoice] = []
    private(set) var loading = true
    private(set) var error: String?
    private var version = 0
    init(context: ForumContext) { self.context = context }
    func reload() async {
        version += 1
        let request = version
        loading = true
        error = nil
        defer { if request == version { loading = false } }
        do {
            let repository = try await context.repository()
            let result = try await repository.townForums()
            let catalog = try await repository.interests()
            guard request == version, !Task.isCancelled else { return }
            forums = result
            pendingInterests = catalog.selected.filter { choice in
                !result.contains { $0.interestId == choice.id }
            }
        } catch {
            guard request == version, !Task.isCancelled else { return }
            forums = []
            pendingInterests = []
            self.error = ForumContext.message(error)
        }
    }
}

@MainActor
@Observable
final class ForumFeedModel {
    let context: ForumContext
    let forumID: String?
    private(set) var posts: [ForumPost] = []
    private(set) var loading = true
    private(set) var loadingMore = false
    private(set) var hasMore = false
    private(set) var error: String?
    private var cursor: String?
    private var version = 0
    init(context: ForumContext, forumID: String?) {
        self.context = context
        self.forumID = forumID
    }
    func reload() async {
        version += 1
        let request = version
        loading = true
        loadingMore = false
        error = nil
        defer { if request == version { loading = false } }
        do {
            let source = try await context.repository()
            let page = try await source.forumPosts(forumID: forumID, cursor: nil)
            guard request == version, !Task.isCancelled else { return }
            posts = page.posts
            cursor = page.posts.last?.id
            hasMore = page.hasMore && cursor != nil
        } catch {
            guard request == version, !Task.isCancelled else { return }
            posts = []
            hasMore = false
            self.error = ForumContext.message(error)
        }
    }
    func loadMore() async {
        guard !loading, !loadingMore, hasMore, let cursor else { return }
        let request = version
        loadingMore = true
        error = nil
        defer { if request == version { loadingMore = false } }
        do {
            let source = try await context.repository()
            let page = try await source.forumPosts(forumID: forumID, cursor: cursor)
            guard request == version, !Task.isCancelled else { return }
            var known = Set(posts.map(\.id))
            let updates = Dictionary(page.posts.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
            posts = posts.map { updates[$0.id] ?? $0 } + page.posts.filter { known.insert($0.id).inserted }
            self.cursor = page.posts.last?.id
            hasMore = page.hasMore && self.cursor != nil && self.cursor != cursor
        } catch {
            guard request == version, !Task.isCancelled else { return }
            self.error = ForumContext.message(error)
        }
    }
}

@MainActor
@Observable
final class ForumPostModel {
    let context: ForumContext
    let id: String
    private(set) var post: ForumPost?
    private(set) var loading = true
    private(set) var busy = false
    private(set) var error: String?
    private var version = 0
    init(context: ForumContext, id: String) {
        self.context = context
        self.id = id
    }
    func reload() async {
        version += 1
        let request = version
        loading = true
        error = nil
        defer { if request == version { loading = false } }
        do {
            let source = try await context.repository()
            let value = try await source.forumPost(id)
            guard request == version, !Task.isCancelled else { return }
            post = value
        } catch {
            guard request == version, !Task.isCancelled else { return }
            post = nil
            self.error = ForumContext.message(error)
        }
    }
    func rsvp() async {
        guard let post, !busy else { return }
        let attending = !post.attending
        await change { try await $0.attendForumPost(self.id, attending: attending) }
    }
    func cancel() async {
        guard post?.isAuthor == true, post?.cancelled == false, !busy else { return }
        await change { try await $0.cancelForumPost(self.id) }
    }
    private func change(_ operation: (any ForumRepository) async throws -> ForumPost) async {
        busy = true
        error = nil
        defer { busy = false }
        do {
            let source = try await context.repository()
            let value = try await operation(source)
            guard !Task.isCancelled else { return }
            post = value
            context.revision += 1
        } catch {
            guard !Task.isCancelled else { return }
            let message = ForumContext.message(error)
            if let error = error as? APIError,
                error == .forumEventOver || error == .forumCancelled || error == .server(404)
            {
                await reload()
            }
            self.error = message
        }
    }
}
