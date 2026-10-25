import Face2FaceCore
import SwiftUI

struct NotificationsView: View {
    let session: SessionModel
    @State private var model: NotificationsModel
    @State private var destination: TownDestination?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var typeSize

    init(session: SessionModel) {
        self.session = session
        _model = State(initialValue: NotificationsModel(session: session))
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    introduction
                    if model.isPreview { previewLabel }
                    if let error = model.error { errorCard(error) }
                    if !model.hasLoaded && model.error == nil {
                        ProgressView("Listening for little hellos…")
                            .frame(maxWidth: .infinity).padding(.vertical, 64)
                            .accessibilityIdentifier("notificationsLoading")
                    } else if model.hasLoaded && model.notifications.isEmpty {
                        emptyInbox
                    } else {
                        ForEach(groups, id: \.day) { group in
                            VStack(alignment: .leading, spacing: 12) {
                                Text(dayTitle(group.day))
                                    .font(.subheadline.weight(.bold))
                                    .foregroundStyle(MeadowPalette.secondaryInk)
                                    .padding(.leading, 4)
                                    .accessibilityAddTraits(.isHeader)
                                ForEach(group.notifications) { notification in
                                    notificationCard(notification)
                                }
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
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 24)
                .padding(.top, 20)
                .padding(.bottom, 32)
            }
            .refreshable { await model.reload() }
        }
        .background(MeadowPalette.grass.ignoresSafeArea())
        .foregroundStyle(MeadowPalette.ink)
        .fontDesign(.rounded)
        .task(id: scenePhase) { if scenePhase == .active { await model.reload() } }
        .sheet(item: $destination) { place in
            TownDestinationView(destination: place, session: session)
        }
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
            Button {
                Task { await model.reload() }
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
            Button("Try again") { Task { await model.reload() } }
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
        if let target = notification.townDestination {
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
        case .postUpdated: "calendar"
        case .postCancelled: "calendar.badge.minus"
        case .postRSVP: "heart.fill"
        case .unknown: "bell.fill"
        }
    }

    fileprivate var symbolInk: Color {
        switch kind {
        case .connected, .postUpdated: MeadowPalette.ink
        default: MeadowPalette.accentInk
        }
    }

    fileprivate var tint: Color {
        switch kind {
        case .encounter, .publicConnection, .unknown: MeadowPalette.accent
        case .connected, .postUpdated: MeadowPalette.treeLight
        case .postCancelled, .postRSVP: MeadowPalette.flower
        }
    }

    fileprivate var townDestination: TownDestination? {
        switch kind {
        case .encounter: connectionId == nil ? nil : .encounters
        case .connected, .publicConnection: connectionId == nil ? nil : .connections
        case .postUpdated, .postCancelled, .postRSVP: forumId == nil ? nil : .forums
        case .unknown: nil
        }
    }
}
