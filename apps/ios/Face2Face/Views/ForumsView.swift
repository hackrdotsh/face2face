import Face2FaceCore
import SwiftUI

enum ForumRoute: Hashable {
    case forum(String, String)
    case event(String)
}
struct ForumEventRoute: Identifiable { let id: String }

struct ForumsView: View {
    let session: SessionModel
    @State private var context: ForumContext
    @State private var model: ForumsModel
    @State private var upcoming: ForumFeedModel
    @State private var tab = 0
    @State private var path: [ForumRoute] = []
    @State private var interests = false
    @State private var composing = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    init(session: SessionModel) {
        self.session = session
        let context = ForumContext(session: session)
        _context = State(initialValue: context)
        _model = State(initialValue: ForumsModel(context: context))
        _upcoming = State(initialValue: ForumFeedModel(context: context, forumID: nil))
    }

    var body: some View {
        NavigationStack(path: $path) {
            VStack(spacing: 0) {
                ForumBar(title: "Forums", backLabel: "Back to town", back: { dismiss() }) {
                    Button {
                        interests = true
                    } label: {
                        Image(systemName: "slider.horizontal.3").frame(width: 44, height: 44)
                    }.accessibilityLabel("Choose interests").accessibilityIdentifier("forumInterests")
                    Button {
                        composing = true
                    } label: {
                        Image(systemName: "plus").frame(width: 44, height: 44)
                    }.disabled(model.forums.isEmpty)
                        .opacity(model.forums.isEmpty ? 0.35 : 1)
                        .accessibilityLabel("New event").accessibilityIdentifier("forumCreate")
                }
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        VStack(alignment: .leading, spacing: 10) {
                            Label("The notice board", systemImage: "pin.fill")
                                .font(.system(.largeTitle, design: .rounded, weight: .bold))
                            Text("Small plans. Good company.")
                                .font(.subheadline).foregroundStyle(MeadowPalette.secondaryInk)
                            Text(
                                "Members of each interest can see the names and photos of hosts and attendees."
                            )
                            .font(.footnote).foregroundStyle(MeadowPalette.secondaryInk)
                        }
                        if context.isPreview { ForumPreviewLabel() }
                        if model.loading && model.forums.isEmpty {
                            ProgressView("Opening the notice board…").frame(maxWidth: .infinity).padding(32)
                        } else if let error = model.error {
                            ForumNotice(
                                title: "Couldn't open the board", message: error,
                                symbol: "wifi.exclamationmark",
                                actionTitle: "Try again", action: { Task { await reload() } })
                        } else if model.forums.isEmpty {
                            ForumNotice(
                                title: model.pendingInterests.isEmpty
                                    ? "Find your kind of people" : "Your circles are growing",
                                message:
                                    model.pendingInterests.isEmpty
                                    ? "Choose a few interests to join their forums and see what's happening."
                                    : "Your interests are saved. New interests open a forum when three people choose them.",
                                symbol: "leaf", actionTitle: "Choose interests", action: { interests = true })
                        } else {
                            if !model.pendingInterests.isEmpty {
                                Text(
                                    "Some of your interests are still growing. New forums open at three members."
                                )
                                .font(.footnote).foregroundStyle(MeadowPalette.secondaryInk)
                            }
                            Picker("Notice board", selection: $tab) {
                                Text("Upcoming").tag(0)
                                Text("Your Forums").tag(1)
                            }.pickerStyle(.segmented).accessibilityIdentifier("forumTabs")
                            if tab == 0 {
                                ForumPostList(model: upcoming, session: session, forums: model.forums)
                            } else {
                                ForEach(model.forums) { forum in
                                    NavigationLink(value: ForumRoute.forum(forum.id, forum.interestName)) {
                                        HStack(spacing: 14) {
                                            Image(systemName: "pin.fill").foregroundStyle(
                                                MeadowPalette.accentInk
                                            )
                                            .frame(width: 44, height: 44).background(
                                                MeadowPalette.accent, in: RoundedRectangle(cornerRadius: 16))
                                            VStack(alignment: .leading, spacing: 5) {
                                                Text(forum.interestName.capitalized).font(.headline)
                                                Text("\(forum.upcomingPostCount) upcoming events").font(
                                                    .subheadline
                                                )
                                                .foregroundStyle(MeadowPalette.secondaryInk)
                                            }.frame(maxWidth: .infinity, alignment: .leading)
                                            Image(systemName: "chevron.right").font(.caption.weight(.bold))
                                        }.padding(18).background(
                                            MeadowPalette.paper, in: RoundedRectangle(cornerRadius: 24))
                                    }.buttonStyle(MeadowPressStyle()).accessibilityIdentifier(
                                        "forum-\(forum.id)")
                                }
                            }
                        }
                    }.padding(24).frame(maxWidth: 560).frame(maxWidth: .infinity)
                }.refreshable { await reload() }
            }
            .background(MeadowPalette.grass.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: ForumRoute.self) { route in
                switch route {
                case .forum(let id, let name):
                    ForumFeedView(forumID: id, name: name, context: context, session: session)
                case .event(let id): ForumEventView(id: id, context: context, session: session)
                }
            }
            .sheet(isPresented: $interests) {
                ForumInterestsView(context: context, session: session) {
                    path = []
                }
            }
            .sheet(isPresented: $composing) {
                ForumEditorView(context: context, forums: model.forums, forumID: nil, post: nil) { _ in
                    Task { await reload() }
                }
            }
            .task(id: context.revision) { await reload() }
            .onChange(of: scenePhase) { if scenePhase == .active { Task { await reload() } } }
        }.foregroundStyle(MeadowPalette.ink).fontDesign(.rounded)
    }
    @MainActor private func reload() async {
        await model.reload()
        if model.error == nil && !model.forums.isEmpty { await upcoming.reload() }
    }
}

private struct ForumFeedView: View {
    let forumID: String
    let name: String
    let context: ForumContext
    let session: SessionModel
    @State private var model: ForumFeedModel
    @State private var composing = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    init(forumID: String, name: String, context: ForumContext, session: SessionModel) {
        self.forumID = forumID
        self.name = name
        self.context = context
        self.session = session
        _model = State(initialValue: ForumFeedModel(context: context, forumID: forumID))
    }
    var body: some View {
        VStack(spacing: 0) {
            ForumBar(title: name.capitalized, backLabel: "Back to forums", back: { dismiss() }) {
                Button {
                    composing = true
                } label: {
                    Image(systemName: "plus").frame(width: 44, height: 44)
                }
                .accessibilityLabel("New event").accessibilityIdentifier("forumCreate")
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("A little plan starts here.").font(.title2.weight(.bold))
                    if context.isPreview { ForumPreviewLabel() }
                    ForumPostList(model: model, session: session, forums: [])
                }.padding(24).frame(maxWidth: 560).frame(maxWidth: .infinity)
            }.refreshable { await model.reload() }
        }
        .background(MeadowPalette.grass.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .task(id: context.revision) { await model.reload() }
        .onChange(of: scenePhase) { if scenePhase == .active { Task { await model.reload() } } }
        .sheet(isPresented: $composing) {
            ForumEditorView(context: context, forums: [], forumID: forumID, post: nil) { _ in
                Task { await model.reload() }
            }
        }
    }
}

private struct ForumPostList: View {
    let model: ForumFeedModel
    let session: SessionModel
    let forums: [TownForum]
    var body: some View {
        VStack(spacing: 16) {
            if let error = model.error {
                ForumNotice(
                    title: "Couldn't load events", message: error, symbol: "wifi.exclamationmark",
                    actionTitle: "Try again", action: { Task { await model.reload() } })
            }
            if model.loading && model.posts.isEmpty {
                ProgressView("Gathering the posters…").padding(32)
            } else if model.posts.isEmpty && model.error == nil {
                ForumNotice(
                    title: "Room for a new plan",
                    message: "No events here yet. Pin the first one to the board.",
                    symbol: "calendar.badge.plus")
            }
            ForEach(model.posts) { post in
                NavigationLink(value: ForumRoute.event(post.id)) {
                    ForumPostCard(
                        post: post, forumName: forums.first { $0.id == post.forumId }?.interestName,
                        session: session)
                }
                .buttonStyle(MeadowPressStyle()).accessibilityIdentifier("forum-post-\(post.id)")
            }
            if model.hasMore {
                Button("Load more events") { Task { await model.loadMore() } }
                    .font(.subheadline.weight(.bold)).frame(minHeight: 44)
                    .disabled(model.loadingMore).accessibilityIdentifier("forumLoadMore")
            }
        }.frame(maxWidth: .infinity)
    }
}

struct ForumPostCard: View {
    let post: ForumPost
    let forumName: String?
    let session: SessionModel
    @Environment(\.dynamicTypeSize) private var typeSize
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Circle().fill(MeadowPalette.accentShadow).frame(width: 6, height: 6).frame(maxWidth: .infinity)
                .accessibilityHidden(true)
            HStack(alignment: .top, spacing: 14) {
                if !typeSize.isAccessibilitySize {
                    VStack(spacing: 3) {
                        Text(post.startDate?.formatted(.dateTime.month(.abbreviated)).uppercased() ?? "EVENT")
                            .font(.system(size: 10, weight: .heavy)).tracking(1)
                        Text(post.startDate?.formatted(.dateTime.day()) ?? "—").font(.title.weight(.bold))
                    }
                    .frame(width: 58).padding(.vertical, 10)
                    .background(MeadowPalette.path, in: RoundedRectangle(cornerRadius: 16))
                }
                VStack(alignment: .leading, spacing: 7) {
                    if let forumName {
                        Text(forumName.capitalized).font(.caption.weight(.semibold)).foregroundStyle(
                            MeadowPalette.secondaryInk)
                    }
                    Text(post.title).font(.headline).fixedSize(horizontal: false, vertical: true)
                    Text(
                        post.startDate?.formatted(
                            date: typeSize.isAccessibilitySize ? .abbreviated : .omitted, time: .shortened)
                            ?? post.startsAt
                    )
                    .font(.subheadline).foregroundStyle(MeadowPalette.secondaryInk)
                }
            }
            if let location = post.location {
                Label(location, systemImage: "mappin").font(.footnote).foregroundStyle(
                    MeadowPalette.secondaryInk
                ).lineLimit(2)
            }
            HStack(spacing: 8) {
                AvatarView(avatar: post.author.avatar, session: session, side: 24)
                Text(post.isAuthor ? "Posted by you" : "Posted by \(post.author.name)").font(.caption)
                Spacer(minLength: 0)
                Text(
                    post.cancelled
                        ? "Cancelled"
                        : post.past ? "Past" : post.attending ? "You're going" : "\(post.attendeeCount) going"
                )
                .font(.caption.weight(.semibold))
            }.foregroundStyle(MeadowPalette.secondaryInk)
        }
        .padding(20).frame(maxWidth: .infinity, alignment: .leading)
        .foregroundStyle(MeadowPalette.ink).multilineTextAlignment(.leading)
        .background(MeadowPalette.paper, in: RoundedRectangle(cornerRadius: 26))
        .overlay(RoundedRectangle(cornerRadius: 26).strokeBorder(MeadowPalette.glassEdge.opacity(0.5)))
    }
}

struct ForumBar<Actions: View>: View {
    let title: String
    let backLabel: String
    let back: () -> Void
    let actions: Actions
    init(title: String, backLabel: String, back: @escaping () -> Void, @ViewBuilder actions: () -> Actions) {
        self.title = title
        self.backLabel = backLabel
        self.back = back
        self.actions = actions()
    }
    var body: some View {
        HStack(spacing: 12) {
            Button(action: back) {
                Image(systemName: "arrow.left").font(.headline).frame(width: 44, height: 44)
                    .background(MeadowPalette.paper, in: Circle())
            }.accessibilityLabel(backLabel)
            Text(title).font(.headline).lineLimit(2).accessibilityIdentifier("forumPageTitle")
            Spacer(minLength: 0)
            actions
        }
        .buttonStyle(MeadowPressStyle()).padding(.horizontal, 24).padding(.top, 12).padding(.bottom, 8)
    }
}

struct ForumPreviewLabel: View {
    var body: some View {
        Label("Preview · sample forums and events", systemImage: "paintbrush.pointed")
            .font(.caption).foregroundStyle(MeadowPalette.secondaryInk).accessibilityIdentifier(
                "forumsPreviewLabel")
    }
}

struct ForumNotice: View {
    let title: String
    let message: String
    let symbol: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil
    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: symbol).font(.title).foregroundStyle(MeadowPalette.trunk).accessibilityHidden(
                true)
            Text(title).font(.headline).multilineTextAlignment(.center)
            Text(message).font(.subheadline).foregroundStyle(MeadowPalette.secondaryInk)
                .multilineTextAlignment(.center)
            if let actionTitle, let action {
                Button(actionTitle, action: action).font(.subheadline.weight(.bold)).padding(.horizontal, 20)
                    .frame(minHeight: 44).background(MeadowPalette.accent, in: Capsule()).foregroundStyle(
                        MeadowPalette.accentInk)
            }
        }.padding(24).frame(maxWidth: .infinity).background(
            MeadowPalette.paper, in: RoundedRectangle(cornerRadius: 26))
    }
}
