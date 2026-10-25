import ActivityKit
import SwiftUI
import WidgetKit

struct BlobCompanionLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: BlobCompanionAttributes.self) { context in
            HStack(spacing: 16) {
                BlobGlyph(seed: context.attributes.seed).frame(width: 72, height: 72)
                VStack(alignment: .leading, spacing: 4) {
                    Text(context.isStale ? "Time to rest." : "Your little plus-one.")
                        .font(.system(.headline, design: .rounded))
                    Text(
                        context.isStale
                            ? "Open face2face to say hello again."
                            : "Just company. No discovery enabled here."
                    )
                    .font(.caption).foregroundStyle(.white.opacity(0.7))
                }
                Spacer(minLength: 0)
            }
            .padding(16)
            .activityBackgroundTint(Color(red: 0.04, green: 0.09, blue: 0.08))
            .activitySystemActionForegroundColor(.white)
            .foregroundStyle(.white)
            .widgetURL(BlobSurface.townURL)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    BlobGlyph(seed: context.attributes.seed).frame(width: 58, height: 58)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Image(systemName: context.isStale ? "moon.zzz" : "sparkles")
                        .font(.title2).foregroundStyle(.mint).padding(12)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(context.isStale ? "Time to rest." : "A little company.").font(.headline)
                            Text("Open your town ↗").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if !context.isStale {
                            Text(
                                timerInterval: context.state.endsAt.addingTimeInterval(
                                    -BlobSurface.sessionDuration)...context.state.endsAt, countsDown: true
                            )
                            .monospacedDigit().font(.caption).frame(width: 52)
                            .accessibilityLabel("Companion time remaining")
                        }
                    }
                    .fontDesign(.rounded)
                    .padding(.bottom, 8)
                }
            } compactLeading: {
                BlobGlyph(seed: context.attributes.seed).frame(width: 28, height: 28)
            } compactTrailing: {
                Image(systemName: context.isStale ? "moon.zzz" : "sparkles").foregroundStyle(.mint)
                    .accessibilityLabel(context.isStale ? "Companion resting" : "Blob companion")
            } minimal: {
                BlobGlyph(seed: context.attributes.seed).frame(width: 24, height: 24)
            }
            .widgetURL(BlobSurface.townURL)
            .keylineTint(.mint)
        }
    }
}

#Preview("Lock Screen", as: .content, using: BlobCompanionAttributes(seed: BlobSurface.previewSeed)) {
    BlobCompanionLiveActivity()
} contentStates: {
    BlobCompanionAttributes.ContentState(endsAt: .now.addingTimeInterval(3600))
}

#Preview(
    "Compact", as: .dynamicIsland(.compact), using: BlobCompanionAttributes(seed: BlobSurface.previewSeed)
) {
    BlobCompanionLiveActivity()
} contentStates: {
    BlobCompanionAttributes.ContentState(endsAt: .now.addingTimeInterval(3600))
}

#Preview(
    "Expanded", as: .dynamicIsland(.expanded), using: BlobCompanionAttributes(seed: BlobSurface.previewSeed)
) {
    BlobCompanionLiveActivity()
} contentStates: {
    BlobCompanionAttributes.ContentState(endsAt: .now.addingTimeInterval(3600))
}

#Preview(
    "Minimal", as: .dynamicIsland(.minimal), using: BlobCompanionAttributes(seed: BlobSurface.previewSeed)
) {
    BlobCompanionLiveActivity()
} contentStates: {
    BlobCompanionAttributes.ContentState(endsAt: .now.addingTimeInterval(3600))
}
