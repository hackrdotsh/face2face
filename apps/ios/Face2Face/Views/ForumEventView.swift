import Face2FaceCore
import SwiftUI

struct ForumEventView: View {
    let context: ForumContext
    let session: SessionModel
    var onBack: (() -> Void)?
    @State private var model: ForumPostModel
    @State private var editing = false
    @State private var attendees = false
    @State private var confirmCancel = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    init(id: String, context: ForumContext, session: SessionModel, onBack: (() -> Void)? = nil) {
        self.context = context
        self.session = session
        self.onBack = onBack
        _model = State(initialValue: ForumPostModel(context: context, id: id))
    }
    var body: some View {
        VStack(spacing: 0) {
            ForumBar(
                title: "Event", backLabel: "Back from event",
                back: { if let onBack { onBack() } else { dismiss() } }
            ) {
                if let post = model.post, post.isAuthor && !post.cancelled {
                    Menu {
                        Button("Edit event", systemImage: "pencil") { editing = true }
                        Button("Cancel event", systemImage: "calendar.badge.minus", role: .destructive) {
                            confirmCancel = true
                        }
                    } label: {
                        Image(systemName: "ellipsis").frame(width: 44, height: 44)
                    }
                    .disabled(model.busy).accessibilityLabel("Event options").accessibilityIdentifier(
                        "forumEventOptions")
                }
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if context.isPreview { ForumPreviewLabel() }
                    if let error = model.error {
                        Text(error).font(.subheadline).foregroundStyle(MeadowPalette.errorInk)
                            .accessibilityIdentifier("forumEventError")
                    }
                    if model.loading && model.post == nil {
                        ProgressView("Unpinning the details…").frame(maxWidth: .infinity).padding(36)
                    } else if let post = model.post {
                        detail(post)
                    } else {
                        ForumNotice(
                            title: "This plan isn't available",
                            message:
                                "It may belong to a forum you haven't joined, or may no longer be available.",
                            symbol: "pin.slash", actionTitle: "Try again",
                            action: { Task { await model.reload() } })
                    }
                }.padding(24).frame(maxWidth: 560).frame(maxWidth: .infinity)
            }.refreshable { if !model.busy { await model.reload() } }
        }
        .background(MeadowPalette.grass.ignoresSafeArea())
        .foregroundStyle(MeadowPalette.ink).fontDesign(.rounded)
        .toolbar(.hidden, for: .navigationBar)
        .task { await model.reload() }
        .onChange(of: scenePhase) {
            if scenePhase == .active && !model.busy { Task { await model.reload() } }
        }
        .sheet(isPresented: $editing) {
            if let post = model.post {
                ForumEditorView(context: context, forums: [], forumID: post.forumId, post: post) { _ in
                    Task { await model.reload() }
                }
            }
        }
        .sheet(isPresented: $attendees) {
            ForumAttendeesView(context: context, postID: model.id, session: session)
        }
        .confirmationDialog("Cancel this event?", isPresented: $confirmCancel, titleVisibility: .visible) {
            Button("Cancel event", role: .destructive) { Task { await model.cancel() } }
                .accessibilityIdentifier("forumConfirmCancel")
            Button("Keep event", role: .cancel) {}
        } message: {
            Text("Attendees will be notified. A cancelled event cannot be edited or accept new RSVPs.")
        }
    }

    private func detail(_ post: ForumPost) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            if post.cancelled || post.past {
                Label(
                    post.cancelled ? "Cancelled" : "This event has finished",
                    systemImage: post.cancelled ? "calendar.badge.minus" : "clock"
                )
                .font(.subheadline.weight(.bold)).foregroundStyle(MeadowPalette.secondaryInk)
                .accessibilityIdentifier("forumEventStatus")
            }
            Text(post.title).font(.system(.largeTitle, design: .rounded, weight: .bold))
                .fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("forumEventHeading")
            HStack(spacing: 10) {
                AvatarView(avatar: post.author.avatar, session: session, side: 36)
                Text(post.isAuthor ? "Hosted by you" : "Hosted by \(post.author.name)").font(.subheadline)
                if post.edited { Text("Edited").font(.caption).foregroundStyle(MeadowPalette.secondaryInk) }
            }
            VStack(alignment: .leading, spacing: 15) {
                Label(
                    post.startDate?.formatted(date: .abbreviated, time: .shortened) ?? post.startsAt,
                    systemImage: "calendar")
                if let end = post.endDate {
                    Label(
                        "Until \(end.formatted(date: .abbreviated, time: .shortened))", systemImage: "clock")
                }
                if let location = post.location { Label(location, systemImage: "mappin.and.ellipse") }
            }
            .font(.subheadline).fixedSize(horizontal: false, vertical: true)
            .padding(20).frame(maxWidth: .infinity, alignment: .leading)
            .background(MeadowPalette.paper, in: RoundedRectangle(cornerRadius: 24))
            if let description = post.description {
                Text(description).font(.body).textSelection(.enabled).fixedSize(
                    horizontal: false, vertical: true)
            }
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    HStack(spacing: -6) {
                        ForEach(Array(post.attendeePreview.prefix(3))) { person in
                            AvatarView(avatar: person.avatar, session: session, side: 30)
                                .padding(2).background(MeadowPalette.paper, in: Circle())
                        }
                    }.accessibilityHidden(true)
                    Text("\(post.attendeeCount) going").font(.subheadline.weight(.semibold))
                        .accessibilityIdentifier("forumAttendeeCount")
                    Spacer(minLength: 0)
                }
                Button("See who's going") { attendees = true }
                    .font(.subheadline.weight(.bold)).frame(minHeight: 44)
                    .accessibilityIdentifier("forumAttendees")
                Button {
                    Task { await model.rsvp() }
                } label: {
                    Label(
                        post.attending
                            ? "Leave event"
                            : post.cancelled
                                ? "Event cancelled" : post.past ? "Event finished" : "I'll be there",
                        systemImage: post.attending ? "checkmark.circle.fill" : "calendar.badge.plus"
                    )
                    .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 15)
                    .background(post.attending ? MeadowPalette.field : MeadowPalette.accent, in: Capsule())
                    .foregroundStyle(post.attending ? MeadowPalette.ink : MeadowPalette.accentInk)
                }
                .buttonStyle(MeadowPressStyle())
                .disabled(model.busy || (!post.attending && (post.cancelled || post.past)))
                .accessibilityIdentifier("forumRSVP")
                Text("Forum members can see your name and photo when you RSVP.")
                    .font(.caption).foregroundStyle(MeadowPalette.secondaryInk)
            }
            .padding(20).frame(maxWidth: .infinity, alignment: .leading)
            .background(MeadowPalette.paper, in: RoundedRectangle(cornerRadius: 24))
            if model.busy { ProgressView("Updating the plan…").frame(maxWidth: .infinity) }
        }
    }
}

struct ForumEventSheet: View {
    let id: String
    let session: SessionModel
    @State private var context: ForumContext
    @Environment(\.dismiss) private var dismiss
    init(id: String, session: SessionModel) {
        self.id = id
        self.session = session
        _context = State(initialValue: ForumContext(session: session))
    }
    var body: some View {
        NavigationStack { ForumEventView(id: id, context: context, session: session, onBack: { dismiss() }) }
    }
}

private struct ForumAttendeesView: View {
    let context: ForumContext
    let postID: String
    let session: SessionModel
    @State private var people: [ForumPerson] = []
    @State private var loading = true
    @State private var error: String?
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(spacing: 0) {
            ForumBar(title: "Who's going", backLabel: "Back to event", back: { dismiss() }) { EmptyView() }
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("A little company for the plan.").font(.title2.weight(.bold))
                    if loading {
                        ProgressView().frame(maxWidth: .infinity).padding(32)
                    } else if let error {
                        ForumNotice(
                            title: "Couldn't load attendees", message: error, symbol: "wifi.exclamationmark",
                            actionTitle: "Try again", action: { Task { await load() } })
                    } else if people.isEmpty {
                        ForumNotice(
                            title: "A seat is waiting", message: "No one has RSVPed yet.", symbol: "person.2")
                    } else {
                        ForEach(people) { person in
                            HStack(spacing: 14) {
                                AvatarView(avatar: person.avatar, session: session, side: 40)
                                Text(person.name).font(.headline)
                                Spacer()
                            }.padding(18).background(
                                MeadowPalette.paper, in: RoundedRectangle(cornerRadius: 22))
                        }
                    }
                }.padding(24).frame(maxWidth: 560).frame(maxWidth: .infinity)
            }
        }
        .foregroundStyle(MeadowPalette.ink).fontDesign(.rounded).background(
            MeadowPalette.grass.ignoresSafeArea()
        )
        .task { await load() }
    }
    @MainActor private func load() async {
        loading = true
        error = nil
        defer { loading = false }
        do {
            let source = try await context.repository()
            let result = try await source.forumAttendees(postID)
            try Task.checkCancellation()
            people = result
        } catch {
            if !Task.isCancelled {
                people = []
                self.error = ForumContext.message(error)
            }
        }
    }
}
