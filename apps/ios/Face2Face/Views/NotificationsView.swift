import Face2FaceCore
import SwiftUI

struct NotificationsView: View {
    let session: SessionModel
    let model: NotificationsModel
    @State private var destination: TownDestination?
    @State private var confirmingClear = false
    @State private var push = PushNotifications.shared
    @State private var event: ForumEventRoute?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(spacing: 0) {
            header
            List {
                Group {
                    introduction
                    if model.isPreview { previewLabel }
                    if let error = model.error { errorCard(error) }
                    if !model.hasLoaded && model.error == nil {
                        ProgressView("Listening for little hellos…")
                            .frame(maxWidth: .infinity).padding(.vertical, 64)
                            .accessibilityIdentifier("notificationsLoading")
                    } else if model.hasLoaded && model.notifications.isEmpty {
                        emptyInbox
                    }
                    ForEach(groups, id: \.day) { group in
                        Text(dayTitle(group.day))
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(MeadowPalette.secondaryInk)
                            .padding(.leading, 4).padding(.top, 12)
                            .accessibilityAddTraits(.isHeader)
                        ForEach(group.notifications) { notification in
                            notificationCard(notification)
                                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                    Button(role: .destructive) {
                                        Task { await model.delete(notification) }
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                    .accessibilityIdentifier("notificationDelete-\(notification.id)")
                                }
                        }
                    }
                    if !model.notifications.isEmpty {
                        Label("You're part of the town.", systemImage: "leaf")
                            .font(.footnote)
                            .foregroundStyle(MeadowPalette.secondaryInk)
                            .frame(maxWidth: .infinity).padding(.vertical, 12)
                    }
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 6, leading: 24, bottom: 6, trailing: 24))
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .contentMargins(.top, 14, for: .scrollContent)
            .refreshable { await reloadAndMarkSeen() }
        }
        .background(MeadowPalette.grass.ignoresSafeArea())
        .foregroundStyle(MeadowPalette.ink)
        .fontDesign(.rounded)
        .task(id: scenePhase) { if scenePhase == .active { await reloadAndMarkSeen() } }
        .onChange(of: push.foregroundArrivals) { Task { await reloadAndMarkSeen() } }
        .sheet(item: $destination) { place in
            TownDestinationView(destination: place, session: session)
        }
        .sheet(item: $event) { route in ForumEventSheet(id: route.id, session: session) }
        .confirmationDialog(
            "Clear all notifications?", isPresented: $confirmingClear, titleVisibility: .visible
        ) {
            Button("Clear All", role: .destructive) { Task { await model.clearAll() } }
                .accessibilityIdentifier("notificationsConfirmClear")
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("They will be removed from all of your devices.")
        }
    }

    private func reloadAndMarkSeen() async {
        await model.reload()
        if model.error == nil { await model.markSeen() }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "arrow.left").font(.headline)
                    .frame(width: 44, height: 44)
                    .background(MeadowPalette.paper, in: Circle())
            }
            .accessibilityLabel("Back to town")
            .accessibilityIdentifier("notificationsBack")
            Text("Notifications").font(.headline)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 0)
            if !model.notifications.isEmpty {
                Button("Clear All") { confirmingClear = true }
                    .font(.subheadline.weight(.bold))
                    .padding(.horizontal, 16).frame(minHeight: 44)
                    .background(MeadowPalette.paper, in: Capsule())
                    .accessibilityIdentifier("notificationsClearAll")
            }
            Button {
                Task { await reloadAndMarkSeen() }
            } label: {
                Image(systemName: "arrow.clockwise").font(.headline)
                    .frame(width: 44, height: 44)
                    .background(MeadowPalette.paper, in: Circle())
            }
            .accessibilityLabel("Refresh notifications")
            .accessibilityIdentifier("notificationsRefresh")
            .disabled(model.isLoading)
        }
        .buttonStyle(MeadowPressStyle())
        .padding(.horizontal, 24).padding(.top, 12).padding(.bottom, 8)
    }

    private var introduction: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: "bell.fill")
                .font(.system(size: 25, weight: .medium))
                .foregroundStyle(MeadowPalette.accentInk)
                .frame(width: 60, height: 60)
                .background(MeadowPalette.accent, in: RoundedRectangle(cornerRadius: 22))
                .rotationEffect(.degrees(-8))
                .accessibilityHidden(true)
            Text("Little hellos,\nlatest happenings.")
                .font(.system(.largeTitle, design: .rounded, weight: .bold))
                .tracking(-0.8)
                .fixedSize(horizontal: false, vertical: true)
            Text("A few things from your corner of the world.")
                .font(.subheadline)
                .foregroundStyle(MeadowPalette.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
        }.padding(.bottom, 4)
    }

    private var previewLabel: some View {
        Label("Preview · sample notifications", systemImage: "paintbrush.pointed")
            .font(.caption.weight(.semibold))
            .foregroundStyle(MeadowPalette.secondaryInk)
            .accessibilityIdentifier("notificationsPreviewLabel")
    }

    private var emptyInbox: some View {
        VStack(spacing: 18) {
            ZStack {
                Circle().fill(MeadowPalette.path).frame(width: 92, height: 92)
                Image(systemName: "bell").font(.system(size: 36, weight: .light))
                    .foregroundStyle(MeadowPalette.trunk)
                Image(systemName: "leaf.fill").font(.system(size: 20))
                    .foregroundStyle(MeadowPalette.treeShade).offset(x: 34, y: 30)
            }.accessibilityHidden(true)
            Text("All quiet in town")
                .font(.title3.weight(.bold))
                .accessibilityIdentifier("notificationsEmpty")
            Text("New encounters, connections, and event updates will appear here.")
                .font(.subheadline)
                .foregroundStyle(MeadowPalette.secondaryInk)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(28).frame(maxWidth: .infinity)
        .background(MeadowPalette.paper, in: RoundedRectangle(cornerRadius: 28))
    }

    private func errorCard(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Couldn't load your updates", systemImage: "wifi.exclamationmark")
                .font(.headline)
                .accessibilityIdentifier("notificationsError")
            Text(message).font(.subheadline).foregroundStyle(MeadowPalette.secondaryInk)
            Button("Try Again") { Task { await reloadAndMarkSeen() } }
                .font(.subheadline.weight(.bold))
                .foregroundStyle(MeadowPalette.accentInk)
                .padding(.horizontal, 18).frame(minHeight: 44)
                .background(MeadowPalette.accent, in: Capsule())
                .disabled(model.isLoading)
                .accessibilityIdentifier("notificationsRetry")
        }
        .padding(20).frame(maxWidth: .infinity, alignment: .leading)
        .background(MeadowPalette.paper, in: RoundedRectangle(cornerRadius: 24))
    }

    @ViewBuilder private func notificationCard(_ notification: InboxNotification) -> some View {
        if [.postUpdated, .postCancelled, .postRSVP].contains(notification.kind), let id = notification.postId
        {
            Button {
                event = ForumEventRoute(id: id)
            } label: {
                cardContents(notification, actionable: true)
            }
            .buttonStyle(MeadowPressStyle()).accessibilityHint("Opens event details")
            .accessibilityIdentifier("notification-\(notification.id)")
        } else if let target = notification.townDestination {
            Button {
                destination = target
            } label: {
                cardContents(notification, actionable: true)
            }
            .buttonStyle(MeadowPressStyle())
            .accessibilityHint("Opens \(target.title.lowercased())")
            .accessibilityIdentifier("notification-\(notification.id)")
        } else {
            cardContents(notification, actionable: false)
        }
    }

    private func cardContents(_ notification: InboxNotification, actionable: Bool) -> some View {
        HStack(alignment: .top, spacing: 14) {
            if !typeSize.isAccessibilitySize {
                Image(systemName: notification.symbol)
                    .font(.system(size: 19, weight: .medium))
                    .foregroundStyle(notification.symbolInk)
                    .frame(width: 44, height: 44)
                    .background(notification.tint, in: RoundedRectangle(cornerRadius: 16))
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 7) {
                Text(notification.title).font(.headline)
                Text(notification.detail)
                    .font(.subheadline)
                    .foregroundStyle(MeadowPalette.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
                Text(
                    notification.createdAt.formatted(
                        .relative(presentation: .numeric, unitsStyle: .abbreviated))
                )
                .font(.caption)
                .foregroundStyle(MeadowPalette.secondaryInk)
                .accessibilityLabel(
                    notification.createdAt.formatted(date: .abbreviated, time: .shortened))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if actionable {
                Image(systemName: "chevron.right").font(.caption.weight(.bold))
                    .foregroundStyle(MeadowPalette.secondaryInk).padding(.top, 15)
                    .accessibilityHidden(true)
            }
        }
        .foregroundStyle(MeadowPalette.ink)
        .multilineTextAlignment(.leading)
        .padding(20)
        .background(MeadowPalette.paper, in: RoundedRectangle(cornerRadius: 24))
        .overlay(RoundedRectangle(cornerRadius: 24).strokeBorder(MeadowPalette.glassEdge.opacity(0.45)))
        .accessibilityElement(children: .combine)
    }

    private var groups: [(day: Date, notifications: [InboxNotification])] {
        Dictionary(grouping: model.notifications) { Calendar.current.startOfDay(for: $0.createdAt) }
            .map { (day: $0.key, notifications: $0.value) }
            .sorted { $0.day > $1.day }
    }

    private func dayTitle(_ date: Date) -> String {
        if Calendar.current.isDateInToday(date) { return "Today" }
        if Calendar.current.isDateInYesterday(date) { return "Yesterday" }
        return date.formatted(date: .abbreviated, time: .omitted)
    }
}

extension InboxNotification {
    fileprivate var title: String {
        switch kind {
        case .encounter: "A new hello"
        case .connected: "It's a connection"
        case .publicConnection: "A little more face to face"
        case .message: "New message"
        case .postUpdated: "A change of plans"
        case .postCancelled: "An event was cancelled"
        case .postRSVP: "One more at the table"
        case .unknown: "An update from your town"
        }
    }

    fileprivate var detail: String {
        switch kind {
        case .encounter:
            sharedInterests.isEmpty
                ? "There's a new chance to connect."
                : "A new chance to connect over \(sharedInterests.joined(separator: " and "))."
        case .connected: "You both said yes. Find your new connection at the café."
        case .publicConnection: "You both chose to share your profiles. Say hello again."
        case .message: "Someone wrote to you. Find the chat at the café."
        case .postUpdated: "An event you're attending has been updated. Check your forums for the latest."
        case .postCancelled: "An event you were attending is no longer happening."
        case .postRSVP: "Someone joined your event. Find the details in your forums."
        case .unknown: "Something new happened. More details may be available in a newer app version."
        }
    }

    fileprivate var symbol: String {
        switch kind {
        case .encounter: "hand.wave.fill"
        case .connected: "cup.and.saucer.fill"
        case .publicConnection: "person.2.fill"
        case .message: "bubble.left.fill"
        case .postUpdated: "calendar"
        case .postCancelled: "calendar.badge.minus"
        case .postRSVP: "heart.fill"
        case .unknown: "bell.fill"
        }
    }

    fileprivate var symbolInk: Color {
        switch kind {
        case .connected, .postUpdated, .message: MeadowPalette.ink
        default: MeadowPalette.accentInk
        }
    }

    fileprivate var tint: Color {
        switch kind {
        case .encounter, .publicConnection, .unknown: MeadowPalette.accent
        case .connected, .postUpdated, .message: MeadowPalette.treeLight
        case .postCancelled, .postRSVP: MeadowPalette.flower
        }
    }

    fileprivate var townDestination: TownDestination? {
        switch kind {
        case .encounter: connectionId == nil ? nil : .encounters
        case .connected, .publicConnection: connectionId == nil ? nil : .connections
        case .message: chatId == nil ? nil : .connections
        case .postUpdated, .postCancelled, .postRSVP: forumId == nil ? nil : .forums
        case .unknown: nil
        }
    }
}
