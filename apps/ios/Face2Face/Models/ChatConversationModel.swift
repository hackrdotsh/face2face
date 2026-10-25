import Face2FaceCore
import Foundation
import Observation

@MainActor
@Observable
final class ChatConversationModel {
    enum State: String { case connecting, live, reconnecting, paused, closed }
    let chatID: String
    let session: SessionModel
    private(set) var summary: ChatSummary?
    private(set) var transcript = ChatTranscript()
    private(set) var state: State = .connecting
    private(set) var error: String?
    private(set) var hasMore = false
    private(set) var loadingOlder = false
    private(set) var theyAreTyping = false
    private(set) var isBlocking = false
    private(set) var isSharingProfiles = false
    private(set) var profileSharingError: String?
    var draft = ""
    private var client: APIClient?
    private var socket: (any ChatSocketTransport)?
    private var generation = 0
    private var sendTasks: [String: Task<Void, Never>] = [:]
    private var heartbeat: Task<Void, Never>?
    private var metadataTask: Task<Void, Never>?
    private var metadataVersion = 0
    private var announcedPublic = false
    private var hasSeenPrivate = false
    private let metadataLoader: (@MainActor () async throws -> ChatSummary)?
    private let consentRecorder: (@MainActor () async throws -> TownConnection)?
    private var typingStop: Task<Void, Never>?
    private var theirTypingStop: Task<Void, Never>?
    private var lastTyping = Date.distantPast
    private var readID: String?
    private var previewPhotos: [String: Data] = [:]
    func localPreviewPhoto(_ id: String) -> Data? { previewPhotos[id] }

    init(
        chatID: String, session: SessionModel,
        loadSummary: (@MainActor () async throws -> ChatSummary)? = nil,
        recordProfileConsent: (@MainActor () async throws -> TownConnection)? = nil
    ) {
        self.chatID = chatID
        self.session = session
        metadataLoader = loadSummary
        consentRecorder = recordProfileConsent
    }

    func run() async {
        guard state != .closed else { return }
        await stop()
        guard !Task.isCancelled else { return }
        generation += 1
        let run = generation
        state = .connecting
        error = nil
        #if DEBUG
            if session.isTownPreview {
                do {
                    let value = try await loadSummary()
                    guard run == generation, !Task.isCancelled else { return }
                    applySummary(value)
                    guard state != .closed else { return }
                    transcript.merge(try ChatPreview.messages(chatID: chatID))
                    state = .live
                    flushPending()
                    startMetadataRefresh(run: run)
                } catch { self.error = "Couldn't open the sample conversation." }
                return
            }
        #endif
        var attempt = 0
        while !Task.isCancelled && run == generation && state != .closed {
            let connection = URLSessionChatSocket()
            do {
                let current = try session.client()
                if let client {
                    guard try await current.usesSameCredential(as: client) else {
                        closePermanently()
                        break
                    }
                } else {
                    client = try await current.capturingCurrentCredential()
                }
                guard let client, run == generation, !Task.isCancelled else { break }
                let latestSummary = try await loadSummary()
                let page = try await client.chatMessages(chatID)
                guard run == generation, !Task.isCancelled else { break }
                applySummary(latestSummary)
                guard state != .closed else { break }
                transcript.merge(page.messages)
                hasMore = hasMore || page.hasMore
                let url = try await client.chatSocketURL(chatID)
                guard run == generation, !Task.isCancelled else { break }
                socket = connection
                try await connection.connect(to: url)
                while !Task.isCancelled && run == generation {
                    let frame = try await connection.receive()
                    guard run == generation, !Task.isCancelled else { break }
                    switch frame {
                    case .ready:
                        state = .live
                        error = nil
                        attempt = 0
                        readID = nil
                        await refreshLatest()
                        guard run == generation, !Task.isCancelled else { break }
                        flushPending()
                        startMetadataRefresh(run: run)
                        heartbeat?.cancel()
                        heartbeat = Task { [weak self] in
                            while !Task.isCancelled {
                                do {
                                    try await Task.sleep(for: .seconds(25))
                                    try await connection.send(.ping)
                                } catch {
                                    await connection.close()
                                    return
                                }
                                guard let self, run == self.generation else { return }
                                self.flushPending()
                            }
                        }
                    case .acknowledgement(let id, let message):
                        transcript.merge([message])
                        transcript.pending.removeAll { $0.id == id }
                        if !transcript.pending.contains(where: { $0.status == .failed }) { error = nil }
                    case .message(let message):
                        transcript.merge([message])
                        if message.from == .them {
                            theyAreTyping = false
                            await markRead()
                        }
                    case .typing(let started):
                        theyAreTyping = started
                        theirTypingStop?.cancel()
                        if started {
                            theirTypingStop = Task { [weak self] in
                                do { try await Task.sleep(for: .seconds(8)) } catch { return }
                                self?.theyAreTyping = false
                            }
                        }
                    case .error(let code, let id):
                        if code == "chat_closed" {
                            closePermanently()
                        } else if let id, let index = transcript.pending.firstIndex(where: { $0.id == id }) {
                            transcript.pending[index].status = .failed
                            if code == "image_not_found" { transcript.pending[index].imageId = nil }
                            error = "That message couldn't be sent. You can retry or remove it."
                        }
                    case .closed: closePermanently()
                    case .pong, .unknown: break
                    }
                    if state == .closed { break }
                }
            } catch ChatSocketError.closed { if run == generation { closePermanently() } } catch APIError
                .unauthenticated
            { if run == generation { closePermanently() } } catch APIError.server(let code)
                where [403, 404, 410].contains(code)
            { if run == generation { closePermanently() } } catch {
                if run == generation && !Task.isCancelled {
                    self.error = "Connection interrupted. Your unconfirmed messages will retry."
                }
            }
            await connection.close()
            guard run == generation, !Task.isCancelled, state != .closed else { break }
            heartbeat?.cancel()
            metadataTask?.cancel()
            metadataVersion += 1
            theyAreTyping = false
            state = .reconnecting
            attempt += 1
            do { try await Task.sleep(for: .seconds(min(15, pow(2, Double(min(attempt - 1, 4)))))) } catch {
                break
            }
        }
    }

    func stop() async {
        generation += 1
        metadataVersion += 1
        heartbeat?.cancel()
        metadataTask?.cancel()
        typingStop?.cancel()
        theirTypingStop?.cancel()
        for task in sendTasks.values { task.cancel() }
        sendTasks = [:]
        let connection = socket
        socket = nil
        theyAreTyping = false
        summary = nil
        isSharingProfiles = false
        profileSharingError = nil
        if state != .closed { state = .paused }
        await connection?.close()
    }

    func shareProfiles() async {
        guard state == .live, !isBlocking, !isSharingProfiles,
            summary?.connection.canOfferProfileSharing == true
        else { return }
        isSharingProfiles = true
        profileSharingError = nil
        metadataVersion += 1
        let request = metadataVersion
        let run = generation
        defer { if run == generation { isSharingProfiles = false } }
        do {
            let connection: TownConnection
            if let consentRecorder {
                connection = try await consentRecorder()
            } else {
                #if DEBUG
                    if session.isTownPreview {
                        connection = try ChatPreview.shareProfiles(chatID: chatID)
                    } else {
                        guard let client, try await session.client().usesSameCredential(as: client) else {
                            closePermanently()
                            return
                        }
                        connection = try await client.agreeToPublicConnection(chatID)
                    }
                #else
                    guard let client, try await session.client().usesSameCredential(as: client) else {
                        closePermanently()
                        return
                    }
                    connection = try await client.agreeToPublicConnection(chatID)
                #endif
            }
            guard run == generation, request == metadataVersion, !Task.isCancelled else { return }
            guard let updated = summary?.replacingConnection(connection) else {
                closePermanently()
                return
            }
            applySummary(updated)
        } catch {
            guard run == generation, request == metadataVersion, !Task.isCancelled else { return }
            if authorizationEnded(error) {
                closePermanently()
                return
            }
            // A timed-out POST may have saved consent. Reconcile once without another POST.
            do {
                let latest = try await loadSummary()
                guard run == generation, request == metadataVersion, !Task.isCancelled else { return }
                applySummary(latest)
            } catch {
                guard run == generation, request == metadataVersion, !Task.isCancelled else { return }
                if authorizationEnded(error) {
                    closePermanently()
                    return
                }
            }
            guard run == generation else { return }
            if summary?.connection.hasChosenProfileSharing != true && summary?.connection.status != "public" {
                profileSharingError =
                    "Couldn't confirm profile sharing. Check the latest status before trying again. Your chat can stay anonymous."
            }
        }
    }

    func refreshConnection() async {
        guard state == .live, !isSharingProfiles else { return }
        metadataVersion += 1
        let request = metadataVersion
        let run = generation
        do {
            let value = try await loadSummary()
            guard run == generation, request == metadataVersion, !Task.isCancelled else { return }
            applySummary(value)
            profileSharingError = nil
        } catch {
            guard run == generation, request == metadataVersion, !Task.isCancelled else { return }
            if authorizationEnded(error) {
                closePermanently()
            } else {
                profileSharingError =
                    "Couldn't refresh profile-sharing status. No new profile information has been revealed."
            }
        }
    }

    private func loadSummary() async throws -> ChatSummary {
        if let metadataLoader { return try await metadataLoader() }
        #if DEBUG
            if session.isTownPreview {
                guard let value = try ChatPreview.chat(chatID) else { throw APIError.server(404) }
                return value
            }
        #endif
        guard let client, try await session.client().usesSameCredential(as: client) else {
            throw APIError.unauthenticated
        }
        return try await client.chat(chatID)
    }

    private func applySummary(_ value: ChatSummary) {
        guard value.id == chatID, value.connection.id == chatID, value.connection.isFriend else {
            closePermanently()
            return
        }
        summary = value
        if value.connection.status == "private" { hasSeenPrivate = true }
        if value.connection.publicTownFriend != nil && hasSeenPrivate && !announcedPublic {
            announcedPublic = true
            PublicConnectionUpdates.shared.confirmedPublic(chatID)
        }
    }

    private func startMetadataRefresh(run: Int) {
        metadataTask?.cancel()
        metadataTask = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(5)) } catch { return }
                guard let self, self.generation == run, self.state == .live else { return }
                await self.refreshConnection()
            }
        }
    }

    func changeDraft() {
        typingStop?.cancel()
        guard state == .live else { return }
        if draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            Task { try? await socket?.send(.typing(false)) }
            return
        }
        if Date().timeIntervalSince(lastTyping) >= 3 {
            lastTyping = Date()
            Task { try? await socket?.send(.typing(true)) }
        }
        typingStop = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(5)) } catch { return }
            try? await self?.socket?.send(.typing(false))
        }
    }

    @discardableResult func send(photo: Data?) -> Bool {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard summary != nil, state != .closed, state != .paused, text.utf16.count <= 4000,
            !text.isEmpty || photo != nil, transcript.pending.count < 10
        else { return false }
        let pending = PendingChatMessage(text: text.isEmpty ? nil : text, photo: photo)
        transcript.pending.append(pending)
        draft = ""
        typingStop?.cancel()
        Task { try? await socket?.send(.typing(false)) }
        startSend(pending.id)
        return true
    }

    func block() async {
        guard !isBlocking, state != .closed else { return }
        isBlocking = true
        defer { isBlocking = false }
        #if DEBUG
            if session.isTownPreview {
                closePermanently()
                error = "Sample connection blocked. No real account was changed."
                return
            }
        #endif
        let run = generation
        do {
            guard let client else { return }
            try await client.blockConnection(chatID)
            guard run == generation || state == .closed else { return }
            closePermanently()
            error = "Connection blocked. This conversation is closed."
        } catch {
            guard run == generation else { return }
            self.error = "Couldn't block this connection. Please try again."
        }
    }

    func retry(_ id: String) {
        guard state != .closed, let index = transcript.pending.firstIndex(where: { $0.id == id }) else {
            return
        }
        transcript.pending[index].status = .sending
        startSend(id)
    }
    func discard(_ id: String) {
        sendTasks[id]?.cancel()
        sendTasks[id] = nil
        transcript.pending.removeAll { $0.id == id }
        if state == .live && !transcript.pending.contains(where: { $0.status == .failed }) { error = nil }
    }

    func refreshLatest() async {
        guard let client else { return }
        let run = generation
        do {
            let page = try await client.chatMessages(chatID)
            guard run == generation, !Task.isCancelled else { return }
            transcript.merge(page.messages)
            hasMore = hasMore || page.hasMore
            await markRead()
        } catch {
            if run == generation {
                if authorizationEnded(error) {
                    closePermanently()
                } else {
                    self.error = "Couldn't refresh the conversation. Reopen it to try again."
                }
            }
        }
    }
    func loadOlder() async {
        guard !loadingOlder, hasMore, let first = transcript.messages.first, let client else { return }
        loadingOlder = true
        let run = generation
        defer { loadingOlder = false }
        do {
            let page = try await client.chatMessages(chatID, before: first.id)
            guard run == generation, !Task.isCancelled else { return }
            transcript.merge(page.messages)
            hasMore = page.hasMore
        } catch {
            if run == generation {
                if authorizationEnded(error) {
                    closePermanently()
                } else {
                    self.error = "Couldn't load earlier messages. Try again."
                }
            }
        }
    }
    private func markRead() async {
        guard state == .live, let id = transcript.messages.last(where: { $0.from == .them })?.id, id != readID
        else { return }
        do {
            try await socket?.send(.read(id))
            readID = id
        } catch {}
    }
    private func flushPending() {
        for item in transcript.pending where item.status != .failed { startSend(item.id) }
    }
    private func startSend(_ id: String) {
        guard state == .live, sendTasks[id] == nil else { return }
        let run = generation
        sendTasks[id] = Task { [weak self] in
            guard let self else { return }
            defer { if run == self.generation { self.sendTasks[id] = nil } }
            do {
                guard run == self.generation, !Task.isCancelled, self.state == .live else { return }
                guard let index = self.transcript.pending.firstIndex(where: { $0.id == id }) else { return }
                #if DEBUG
                    if self.session.isTownPreview {
                        let item = self.transcript.pending[index]
                        let message = try ChatPreview.acknowledge(item)
                        if let photo = item.photo { self.previewPhotos[message.id] = photo }
                        self.transcript.merge([message])
                        return
                    }
                #endif
                if self.transcript.pending[index].imageId == nil,
                    let photo = self.transcript.pending[index].photo
                {
                    self.transcript.pending[index].status = .uploading
                    guard let client = self.client else { return }
                    let image = try await client.uploadChatPhoto(self.chatID, jpeg: photo)
                    guard run == self.generation, !Task.isCancelled,
                        let current = self.transcript.pending.firstIndex(where: { $0.id == id })
                    else { return }
                    self.transcript.pending[current].imageId = image.id
                }
                guard run == self.generation, !Task.isCancelled,
                    let current = self.transcript.pending.firstIndex(where: { $0.id == id })
                else { return }
                self.transcript.pending[current].status = .sending
                let item = self.transcript.pending[current]
                try await self.socket?.send(.send(clientId: id, text: item.text, imageId: item.imageId))
            } catch {
                guard run == self.generation, !Task.isCancelled else { return }
                if self.authorizationEnded(error) {
                    self.closePermanently()
                    return
                }
                guard let index = self.transcript.pending.firstIndex(where: { $0.id == id }) else { return }
                self.transcript.pending[index].status = .failed
                self.error = "Couldn't send this message. Retry when connected, or remove it."
            }
        }
    }
    private func closePermanently() {
        guard state != .closed else { return }
        generation += 1
        state = .closed
        draft = ""
        summary = nil
        transcript = ChatTranscript()
        previewPhotos = [:]
        error = "This conversation is no longer available. It may have been blocked or your session ended."
        heartbeat?.cancel()
        metadataTask?.cancel()
        metadataVersion += 1
        isSharingProfiles = false
        profileSharingError = nil
        typingStop?.cancel()
        theirTypingStop?.cancel()
        theyAreTyping = false
        for task in sendTasks.values { task.cancel() }
        sendTasks = [:]
        let connection = socket
        socket = nil
        Task { await connection?.close() }
    }
    private func authorizationEnded(_ error: any Error) -> Bool {
        guard let error = error as? APIError else { return false }
        return error == .unauthenticated || error == .server(403) || error == .server(404)
            || error == .server(410)
    }
}
