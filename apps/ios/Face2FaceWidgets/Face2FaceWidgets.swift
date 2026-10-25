import SwiftUI
import WidgetKit

@main
struct Face2FaceWidgets: WidgetBundle {
    var body: some Widget {
        CampfireWidget()
        BlobCompanionLiveActivity()
    }
}

struct CampfireEntry: TimelineEntry {
    let date: Date
    let snapshot: CampfireSnapshot
    var smallPage = 0
    var mediumPage = 0
    var largePage = 0
}

struct CampfireProvider: TimelineProvider {
    func placeholder(in context: Context) -> CampfireEntry { .preview }

    func getSnapshot(in context: Context, completion: @escaping (CampfireEntry) -> Void) {
        completion(context.isPreview ? .preview : entry(at: .now))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<CampfireEntry>) -> Void) {
        let now = Date()
        let current = entry(at: now)
        let expiry =
            current.snapshot.status == .ready
            ? current.snapshot.expiresAt : now.addingTimeInterval(CampfireSnapshot.lifetime)
        let redacted = CampfireEntry(date: expiry, snapshot: current.snapshot.visible(at: expiry))
        completion(Timeline(entries: [current, redacted], policy: .after(expiry)))
    }

    private func entry(at date: Date) -> CampfireEntry {
        CampfireEntry(
            date: date, snapshot: CampfireStore.read(at: date),
            smallPage: CampfireStore.page(size: 4), mediumPage: CampfireStore.page(size: 6),
            largePage: CampfireStore.page(size: 10))
    }
}

struct CampfireWidget: Widget {
    var body: some WidgetConfiguration {
        // Preserve the installed widget kind across the upgrade from the daily blob.
        StaticConfiguration(kind: "DailyBlob", provider: CampfireProvider()) { entry in
            CampfireWidgetView(entry: entry)
                .containerBackground(for: .widget) {
                    LinearGradient(
                        colors: [
                            Color(red: 0.06, green: 0.16, blue: 0.2),
                            Color(red: 0.02, green: 0.065, blue: 0.09),
                        ], startPoint: .topLeading, endPoint: .bottomTrailing)
                }
                .widgetURL(BlobSurface.connectionsURL)
                .privacySensitive()
        }
        .configurationDisplayName("Around the campfire")
        .description(
            "Your accepted friends, gathered as blobs. Turn the pages to see everyone. Not live presence; private friends stay anonymous. Enable sharing in face2face Settings."
        )
        .supportedFamilies([
            .systemSmall, .systemMedium, .systemLarge, .accessoryCircular, .accessoryRectangular,
            .accessoryInline,
        ])
    }
}

struct CampfireWidgetView: View {
    let entry: CampfireEntry
    @Environment(\.widgetFamily) private var family

    private var snapshot: CampfireSnapshot { entry.snapshot.visible(at: entry.date) }
    private var size: Int { family == .systemLarge ? 10 : family == .systemSmall ? 4 : 6 }
    private var page: Int {
        let value =
            family == .systemLarge
            ? entry.largePage : family == .systemSmall ? entry.smallPage : entry.mediumPage
        let count = snapshot.pageCount(size: size)
        return (value % count + count) % count
    }
    private var count: String {
        "\(snapshot.guests.count) \(snapshot.guests.count == 1 ? "friend" : "friends")"
    }

    var body: some View {
        Group {
            switch family {
            case .accessoryInline:
                Label(
                    snapshot.status == .ready ? "\(count) by the fire" : "Your campfire awaits",
                    systemImage: "flame")
            case .accessoryCircular:
                VStack(spacing: 1) {
                    Image(systemName: "flame.fill").font(.title3)
                    Text(snapshot.status == .ready ? "\(snapshot.guests.count)" : "—").font(.caption.bold())
                }.accessibilityLabel(
                    snapshot.status == .ready
                        ? "\(count) in your saved campfire, not live attendance" : message)
            case .accessoryRectangular:
                HStack(spacing: 8) {
                    Image(systemName: "flame.fill").font(.title2).widgetAccentable()
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Your campfire").font(.headline)
                        Text(snapshot.status == .ready ? "\(count) · saved circle" : message).font(.caption)
                    }
                }
            default:
                VStack(spacing: 0) {
                    HStack(alignment: .firstTextBaseline) {
                        Label("CAMPFIRE", systemImage: "flame.fill")
                            .font(.system(size: 10, weight: .heavy, design: .rounded)).tracking(1.5)
                            .foregroundStyle(Color(red: 1, green: 0.76, blue: 0.48))
                        Spacer(minLength: 0)
                        if family != .systemSmall, snapshot.status == .ready {
                            Text(count).font(.caption.weight(.semibold)).foregroundStyle(.white.opacity(0.7))
                        }
                    }
                    CampfireScene(
                        ownSeed: snapshot.ownSeed, guests: snapshot.page(page, size: size),
                        showsNames: family != .systemSmall
                    )
                    .accessibilityElement(children: .ignore)
                    .accessibilityHidden(false)
                    .accessibilityLabel(
                        "Saved campfire. You\(snapshot.page(page, size: size).map { ", \($0.name)" }.joined()). Not live attendance."
                    )
                    if snapshot.status == .ready {
                        if snapshot.pageCount(size: size) > 1 {
                            HStack(spacing: 4) {
                                pageButton(step: -1)
                                Spacer(minLength: 0)
                                Text("\(page + 1) / \(snapshot.pageCount(size: size))").font(
                                    .caption.monospacedDigit().weight(.semibold)
                                )
                                .accessibilityLabel(
                                    "Page \(page + 1) of \(snapshot.pageCount(size: size)); \(count) total")
                                Spacer(minLength: 0)
                                pageButton(step: 1)
                            }
                        } else {
                            Text(
                                snapshot.guests.isEmpty
                                    ? "A seat for your next hello ↗" : "\(count). One little fire. ↗"
                            )
                            .font(.system(.caption, design: .rounded, weight: .semibold)).lineLimit(2)
                        }
                        if family == .systemLarge {
                            HStack(spacing: 4) {
                                Image(systemName: "clock")
                                Text("Saved ") + Text(snapshot.updatedAt, style: .time)
                                Text("· not live presence")
                            }.font(.system(size: 9)).foregroundStyle(.white.opacity(0.55)).padding(.top, 6)
                        }
                    } else {
                        Text(message).font(.system(.caption, design: .rounded, weight: .semibold))
                            .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                    }
                }
                .foregroundStyle(.white)
            }
        }
        .fontDesign(.rounded)
    }

    private var message: String {
        switch snapshot.status {
        case .ready: "Your fire is ready"
        case .disabled: "Enable friends in widget Settings ↗"
        case .signedOut: "Sign in to gather your friends ↗"
        case .unavailable: "Open face2face to refresh friends ↗"
        case .expired: "Time to gather your friends again ↗"
        }
    }

    private func pageButton(step: Int) -> some View {
        Button(intent: CampfirePageIntent(step: step, size: size)) {
            Image(systemName: step < 0 ? "chevron.left" : "chevron.right")
                .font(.caption.bold()).frame(width: 32, height: 28)
                .background(.white.opacity(0.1), in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(step < 0 ? "Previous campfire friends" : "Next campfire friends")
    }
}

extension CampfireEntry {
    static var preview: Self {
        Self(
            date: .now,
            snapshot: .init(
                status: .ready,
                guests: [
                    .init(id: 0, name: "Ava", seed: "AQIDBAUGBwgJCgsMDQ4PEA", isAnonymous: false),
                    .init(id: 1, name: "Noor", seed: "BBCCAQUGBwgJCgsMDQ4PEA", isAnonymous: false),
                    .init(id: 2, name: "Cleo", seed: "CMCCAQUGBwgJCgsMDQ4PEA", isAnonymous: false),
                    .init(id: 3, name: "Anonymous friend", seed: "BAACAQUGBwgJCgsMDQ4PEA", isAnonymous: true),
                    .init(id: 4, name: "Max", seed: "CCBBAQUGBwgJCgsMDQ4PEA", isAnonymous: false),
                    .init(id: 5, name: "Jay", seed: "AABBAQUGBwgJCgsMDQ4PEA", isAnonymous: false),
                ]))
    }
}

#Preview("Small", as: .systemSmall) { CampfireWidget() } timeline: { CampfireEntry.preview }
#Preview("Medium", as: .systemMedium) { CampfireWidget() } timeline: { CampfireEntry.preview }
#Preview("Large", as: .systemLarge) { CampfireWidget() } timeline: { CampfireEntry.preview }
#Preview("Lock Screen", as: .accessoryRectangular) { CampfireWidget() } timeline: { CampfireEntry.preview }
