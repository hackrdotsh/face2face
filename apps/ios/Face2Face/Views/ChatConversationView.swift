import Face2FaceCore
import PhotosUI
import SwiftUI

struct ChatConversationView: View {
    let session: SessionModel
    @State private var model: ChatConversationModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var pickedPhoto: PhotosPickerItem?
    @State private var attachment: Data?
    @State private var preparing = false
    @State private var photoError: String?
    @State private var showLeaveWarning = false
    @State private var showBlockWarning = false
    @State private var selectedImage: ChatImage?
    @State private var followLatest = true
    @FocusState private var focused: Bool

    init(chatID: String, session: SessionModel) {
        self.session = session
        _model = State(initialValue: ChatConversationModel(chatID: chatID, session: session))
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            if session.isTownPreview {
                Text("Preview · messages stay on this device").font(.caption)
                    .foregroundStyle(MeadowPalette.secondaryInk).padding(.vertical, 6)
            }
            if let error = model.error {
                Text(error).font(.caption).foregroundStyle(MeadowPalette.errorInk)
                    .padding(.horizontal, 20).padding(.vertical, 8)
                    .accessibilityIdentifier("chatError")
            }
            if model.state == .closed {
                ContentUnavailableView(
                    "This table is closed", systemImage: "lock",
                    description: Text("You can no longer send or receive messages in this conversation.")
                )
                .accessibilityIdentifier("chatClosed")
            } else {
                conversation
                composer.disabled(model.isBlocking)
            }
        }
        .background(MeadowPalette.grass.ignoresSafeArea())
        .foregroundStyle(MeadowPalette.ink).fontDesign(.rounded)
        .toolbar(.hidden, for: .navigationBar, .tabBar)
        .task(id: scenePhase) {
            if scenePhase == .active { await model.run() } else { await model.stop() }
        }
        .onDisappear { Task { await model.stop() } }
        .task(id: pickedPhoto) { await preparePickedPhoto() }
        .onChange(of: model.draft) { model.changeDraft() }
        .onChange(of: model.state) {
            if model.state == .closed {
                attachment = nil
                pickedPhoto = nil
                focused = false
            }
        }
        .confirmationDialog(
            "Leave unconfirmed messages?", isPresented: $showLeaveWarning, titleVisibility: .visible
        ) {
            Button("Leave conversation", role: .destructive) { dismiss() }
            Button("Keep chatting", role: .cancel) {}
        } message: {
            Text(
                "Unconfirmed messages are kept only while this conversation is open. They may not have been sent."
            )
        }
        .confirmationDialog(
            "Block this connection?", isPresented: $showBlockWarning, titleVisibility: .visible
        ) {
            Button("Block connection", role: .destructive) { Task { await model.block() } }
                .accessibilityIdentifier("chatConfirmBlock")
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This closes the chat for both of you and prevents future connections with this person.")
        }
        .sheet(item: $selectedImage) { image in
            NavigationStack {
                ChatRemotePhoto(path: image.variants.original.path, session: session)
                    .padding().frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(MeadowPalette.grass.ignoresSafeArea())
                    .navigationTitle("Photo").navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) { Button("Done") { selectedImage = nil } }
                    }
            }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Button {
                focused = false
                if model.transcript.pending.isEmpty { dismiss() } else { showLeaveWarning = true }
            } label: {
                Image(systemName: "arrow.left").font(.headline).frame(width: 44, height: 44)
                    .background(MeadowPalette.paper, in: Circle())
            }
            .accessibilityLabel("Back to connections").accessibilityIdentifier("chatBack")
            ChatIdentityAvatar(chat: model.summary, session: session)
            VStack(alignment: .leading, spacing: 3) {
                Text(model.summary?.title ?? "Conversation").font(.headline).lineLimit(2)
                    .accessibilityIdentifier("chatTitle")
                Text(model.state == .live ? "Chat connected" : model.state.rawValue.capitalized)
                    .font(.caption).foregroundStyle(MeadowPalette.secondaryInk)
            }
            Spacer(minLength: 0)
            if model.summary != nil && model.state != .closed {
                Menu {
                    Button("Block connection", systemImage: "hand.raised", role: .destructive) {
                        focused = false
                        showBlockWarning = true
                    }
                } label: {
                    Image(systemName: "ellipsis").frame(width: 44, height: 44)
                }
                .disabled(model.isBlocking)
                .accessibilityLabel("Conversation options").accessibilityIdentifier("chatOptions")
            }
        }.padding(.horizontal, 20).padding(.vertical, 12)
    }

    private var conversation: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 12) {
                    if model.hasMore {
                        Button("Earlier messages") { Task { await model.loadOlder() } }
                            .disabled(model.loadingOlder).font(.subheadline.weight(.semibold))
                    }
                    if model.transcript.messages.isEmpty && model.transcript.pending.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "cup.and.saucer").font(.largeTitle)
                            Text(
                                model.summary == nil
                                    ? "Opening your conversation…" : "Start with a little hello."
                            )
                            .font(.headline)
                            Text("Your identity stays hidden until you both choose to go public.")
                                .font(.footnote).multilineTextAlignment(.center)
                        }.foregroundStyle(MeadowPalette.secondaryInk).padding(.vertical, 64)
                    }
                    ForEach(model.transcript.messages) { message in
                        HStack {
                            if message.from == .you { Spacer(minLength: 40) }
                            VStack(alignment: .leading, spacing: 8) {
                                if let image = message.image {
                                    Button {
                                        selectedImage = image
                                    } label: {
                                        ChatRemotePhoto(path: image.variants.preview.path, session: session)
                                            .frame(width: 210, height: imageHeight(image))
                                            .clipShape(RoundedRectangle(cornerRadius: 14))
                                    }.buttonStyle(.plain).accessibilityLabel("Open photo")
                                }
                                if let data = model.localPreviewPhoto(message.id),
                                    let image = UIImage(data: data)
                                {
                                    Image(uiImage: image).resizable().scaledToFit().frame(maxWidth: 210)
                                        .clipShape(RoundedRectangle(cornerRadius: 14))
                                        .accessibilityLabel("Photo you sent in preview")
                                        .accessibilityIdentifier("chatPreviewSentPhoto")
                                }
                                if let text = message.text, !text.isEmpty {
                                    Text(text).font(.body).textSelection(.enabled)
                                }
                                Text(messageTime(message.createdAt)).font(.caption2)
                                    .foregroundStyle(
                                        message.from == .you
                                            ? MeadowPalette.accentInk.opacity(0.75)
                                            : MeadowPalette.secondaryInk)
                            }
                            .padding(14)
                            .foregroundStyle(
                                message.from == .you ? MeadowPalette.accentInk : MeadowPalette.ink
                            )
                            .background(
                                message.from == .you ? MeadowPalette.accent : MeadowPalette.paper,
                                in: RoundedRectangle(cornerRadius: 22)
                            )
                            .accessibilityIdentifier("message-\(message.id)")
                            if message.from == .them { Spacer(minLength: 40) }
                        }
                    }
                    ForEach(model.transcript.pending) { item in
                        HStack {
                            Spacer(minLength: 40)
                            VStack(alignment: .leading, spacing: 8) {
                                if let data = item.photo, let image = UIImage(data: data) {
                                    Image(uiImage: image).resizable().scaledToFit().frame(maxWidth: 190)
                                }
                                if let text = item.text { Text(text) }
                                Text(
                                    item.status == .failed
                                        ? "Not sent"
                                        : model.state != .live
                                            ? "Waiting to reconnect…"
                                            : item.status == .uploading
                                                ? "Uploading photo…" : "Waiting for confirmation…"
                                )
                                .font(.caption)
                                if item.status == .failed {
                                    HStack {
                                        Button("Retry") { model.retry(item.id) }.frame(minHeight: 44)
                                        Button("Remove", role: .destructive) { model.discard(item.id) }.frame(
                                            minHeight: 44)
                                    }.font(.caption.weight(.semibold))
                                }
                            }
                            .padding(14).background(
                                MeadowPalette.paper.opacity(0.8), in: RoundedRectangle(cornerRadius: 22))
                        }
                    }
                    if model.theyAreTyping {
                        Text("Typing…").font(.caption).foregroundStyle(MeadowPalette.secondaryInk)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    Color.clear.frame(height: 1).id("chatBottom")
                }.padding(.horizontal, 20).padding(.vertical, 16)
            }
            .scrollDismissesKeyboard(.interactively)
            .simultaneousGesture(DragGesture().onChanged { _ in followLatest = false })
            .overlay(alignment: .bottomTrailing) {
                if !followLatest {
                    Button("Latest ↓") {
                        followLatest = true
                        proxy.scrollTo("chatBottom", anchor: .bottom)
                    }
                    .font(.caption.weight(.bold)).padding(12)
                    .background(MeadowPalette.paper, in: Capsule()).padding(12)
                }
            }
            .onChange(of: model.transcript.messages.last?.id) {
                if followLatest { proxy.scrollTo("chatBottom", anchor: .bottom) }
            }
            .onChange(of: model.transcript.pending.count) {
                if followLatest { proxy.scrollTo("chatBottom", anchor: .bottom) }
            }
            .onChange(of: focused) {
                if focused {
                    followLatest = true
                    proxy.scrollTo("chatBottom", anchor: .bottom)
                }
            }
        }
    }

    private var composer: some View {
        VStack(spacing: 10) {
            if let data = attachment, let image = UIImage(data: data) {
                HStack {
                    Image(uiImage: image).resizable().scaledToFit().frame(width: 60, height: 60)
                    Text("Photo ready").font(.caption)
                    Spacer()
                    Button {
                        attachment = nil
                        pickedPhoto = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill").frame(width: 44, height: 44)
                    }.accessibilityLabel("Remove attached photo")
                }.padding(.horizontal, 4)
            }
            if let photoError { Text(photoError).font(.caption).foregroundStyle(MeadowPalette.errorInk) }
            if model.draft.utf16.count > 3900 {
                Text("\(model.draft.utf16.count)/4000").font(.caption).foregroundStyle(
                    MeadowPalette.secondaryInk)
            }
            HStack(alignment: .bottom, spacing: 10) {
                PhotosPicker(selection: $pickedPhoto, matching: .images) {
                    Image(systemName: preparing ? "hourglass" : "photo.badge.plus")
                        .font(.system(size: 21)).frame(width: 44, height: 44)
                        .background(MeadowPalette.field, in: Circle())
                }
                .disabled(preparing || model.summary == nil)
                .accessibilityLabel("Attach photo").accessibilityIdentifier("chatAttachPhoto")
                TextField("A little hello…", text: $model.draft, axis: .vertical)
                    .lineLimit(1...5).focused($focused).padding(.vertical, 12)
                    .accessibilityIdentifier("chatDraft")
                Button {
                    followLatest = true
                    if model.send(photo: attachment) {
                        attachment = nil
                        pickedPhoto = nil
                        photoError = nil
                    }
                } label: {
                    Image(systemName: "paperplane.fill").font(.system(size: 18, weight: .semibold))
                        .frame(width: 44, height: 44).background(MeadowPalette.accent, in: Circle())
                        .foregroundStyle(MeadowPalette.accentInk)
                }
                .disabled(
                    preparing || model.summary == nil || model.draft.utf16.count > 4000
                        || model.transcript.pending.count >= 10
                        || (model.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            && attachment == nil)
                )
                .accessibilityLabel("Send message").accessibilityIdentifier("chatSend")
            }
        }
        .padding(14).background(MeadowPalette.paper)
    }

    @MainActor private func preparePickedPhoto() async {
        guard let pickedPhoto else { return }
        preparing = true
        photoError = nil
        defer { preparing = false }
        do {
            guard let data = try await pickedPhoto.loadTransferable(type: Data.self) else {
                throw PhotoError.unreadable
            }
            let jpeg = try await Task.detached(priority: .userInitiated) { try ChatPhoto.jpeg(data) }.value
            try Task.checkCancellation()
            guard model.state != .closed else { return }
            attachment = jpeg
        } catch { if !Task.isCancelled { photoError = "Couldn't prepare this photo. Try a smaller image." } }
    }
    private func imageHeight(_ image: ChatImage) -> CGFloat {
        let variant = image.variants.preview
        return min(260, max(90, 210 * CGFloat(variant.height) / CGFloat(max(1, variant.width))))
    }
    private func messageTime(_ timestamp: String) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let fractional = formatter.date(from: timestamp)
        formatter.formatOptions = [.withInternetDateTime]
        return (fractional ?? formatter.date(from: timestamp))?.formatted(date: .omitted, time: .shortened)
            ?? ""
    }
}

private struct ChatRemotePhoto: View {
    let path: String
    let session: SessionModel
    @State private var image: UIImage?
    @State private var failed = false
    @State private var attempt = 0
    var body: some View {
        Group {
            if let image {
                Image(uiImage: image).resizable().scaledToFit()
            } else if failed {
                Button {
                    attempt += 1
                } label: {
                    Label("Reload photo", systemImage: "arrow.clockwise")
                }
                .font(.caption).padding().accessibilityLabel(
                    "Reload photo; reopen the conversation if its link expired")
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task(id: "\(path)-\(attempt)") {
            guard path.hasPrefix("/media/chats/"), let url = session.mediaURL(for: path),
                let base = URL(string: session.serverAddress), url.scheme == base.scheme,
                url.host == base.host, url.port == base.port
            else {
                failed = true
                return
            }
            failed = false
            do {
                // Signed URL only: no bearer header, cookies, redirect following or disk cache.
                let response = try await URLSessionTransport().send(URLRequest(url: url))
                guard response.status == 200, response.data.count <= 20 * 1024 * 1024,
                    let decoded = UIImage(data: response.data)
                else {
                    failed = true
                    return
                }
                try Task.checkCancellation()
                image = decoded
            } catch { if !Task.isCancelled { failed = true } }
        }
    }
}
