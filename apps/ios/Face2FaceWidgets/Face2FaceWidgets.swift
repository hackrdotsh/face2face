import SwiftUI
import WidgetKit

@main
struct Face2FaceWidgets: WidgetBundle {
    var body: some Widget {
        DailyBlobWidget()
        BlobCompanionLiveActivity()
    }
}

struct DailyBlobEntry: TimelineEntry {
    let date: Date
    var seed: String { BlobSurface.dailySeed(at: date) }
}

struct DailyBlobProvider: TimelineProvider {
    func placeholder(in context: Context) -> DailyBlobEntry { DailyBlobEntry(date: .now) }

    func getSnapshot(in context: Context, completion: @escaping (DailyBlobEntry) -> Void) {
        completion(DailyBlobEntry(date: .now))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<DailyBlobEntry>) -> Void) {
        let now = Date()
        let tomorrow = Date(timeIntervalSince1970: (floor(now.timeIntervalSince1970 / 86_400) + 1) * 86_400)
        completion(
            Timeline(
                entries: [DailyBlobEntry(date: now), DailyBlobEntry(date: tomorrow)], policy: .after(tomorrow)
            ))
    }
}

struct DailyBlobWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "DailyBlob", provider: DailyBlobProvider()) { entry in
            DailyBlobView(entry: entry)
                .containerBackground(for: .widget) {
                    LinearGradient(
                        colors: [Color(red: 0.09, green: 0.18, blue: 0.17), .black], startPoint: .topLeading,
                        endPoint: .bottomTrailing)
                }
                .widgetURL(BlobSurface.townURL)
        }
        .configurationDisplayName("A little company")
        .description(
            "A new decorative blob each day. Tap to visit your town; no account or discovery data is shown."
        )
        .supportedFamilies([
            .systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular, .accessoryInline,
        ])
    }
}

struct DailyBlobView: View {
    let entry: DailyBlobEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        Group {
            switch family {
            case .accessoryInline:
                Label("Visit your little town", systemImage: "sparkles")
            case .accessoryCircular:
                BlobGlyph(seed: entry.seed).widgetAccentable()
                    .accessibilityHidden(false)
                    .accessibilityLabel("Daily decorative blob. Open face2face.")
            case .accessoryRectangular:
                HStack {
                    BlobGlyph(seed: entry.seed).frame(width: 44, height: 44).widgetAccentable()
                    VStack(alignment: .leading) {
                        Text("face2face").font(.headline)
                        Text("Visit your little town").font(.caption)
                    }
                }
            default:
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("FACE2FACE").font(.system(size: 10, weight: .heavy, design: .rounded)).tracking(
                            2
                        )
                        .foregroundStyle(.white.opacity(0.65))
                        if family == .systemMedium {
                            Text("Small world.\nGood company.").font(
                                .system(.title3, design: .rounded, weight: .bold))
                            Text("Visit your town ↗").font(.caption).foregroundStyle(.white.opacity(0.75))
                        } else {
                            BlobGlyph(seed: entry.seed).frame(maxWidth: .infinity, maxHeight: .infinity)
                            Text("See you in town ↗").font(
                                .system(.caption, design: .rounded, weight: .semibold))
                        }
                    }
                    if family == .systemMedium {
                        Spacer(minLength: 0)
                        BlobGlyph(seed: entry.seed).frame(width: 108, height: 108)
                    }
                }
                .foregroundStyle(.white)
            }
        }
        .fontDesign(.rounded)
        .accessibilityElement(children: .combine)
    }
}

#Preview("Small", as: .systemSmall) {
    DailyBlobWidget()
} timeline: {
    DailyBlobEntry(date: .now)
}

#Preview("Medium", as: .systemMedium) {
    DailyBlobWidget()
} timeline: {
    DailyBlobEntry(date: .now)
}

#Preview("Lock Screen", as: .accessoryRectangular) {
    DailyBlobWidget()
} timeline: {
    DailyBlobEntry(date: .now)
}
