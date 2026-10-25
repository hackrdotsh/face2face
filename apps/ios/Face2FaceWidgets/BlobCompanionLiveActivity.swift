import ActivityKit
import SwiftUI
import WidgetKit

struct BlobCompanionLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: BlobCompanionAttributes.self) { context in
            HStack(spacing: 14) {
                IslandBlob(seed: context.attributes.seed, pulse: context.state.pulse)
                    .frame(width: 64, height: 64)
                VStack(alignment: .leading, spacing: 5) {
                    Text(title(context)).font(.system(.headline, design: .rounded))
                    Text(
                        context.state.signal.mode == .off
                            ? "A little company for the road."
                            : "Radio strength only · not distance or identity"
                    )
                    .font(.caption).foregroundStyle(.white.opacity(0.65))
                    if context.state.signal.mode != .off {
                        SignalBars(levels: levels(context)).frame(height: 28)
                    }
                }
                Spacer(minLength: 0)
                if context.state.endsAt > Date() { waveButton }
            }
            .padding(18)
            .activityBackgroundTint(Color(red: 0.035, green: 0.09, blue: 0.1))
            .activitySystemActionForegroundColor(.white)
            .foregroundStyle(.white)
            .widgetURL(BlobSurface.townURL)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    IslandBlob(seed: context.attributes.seed, pulse: context.state.pulse)
                        .frame(width: 48, height: 48)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if context.state.signal.mode == .off {
                        Image(systemName: "sparkles").font(.title2).foregroundStyle(.mint).padding(8)
                    } else {
                        SignalBars(levels: levels(context)).frame(height: 34).padding(.top, 6)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack(spacing: 8) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(title(context)).font(.subheadline.bold()).lineLimit(2)
                            Text(
                                context.state.signal.mode == .off
                                    ? "Open your town ↗" : "Signal, not distance"
                            )
                            .font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer(minLength: 0)
                        if context.state.endsAt > Date() { waveButton }
                        if !context.isStale {
                            Text(
                                timerInterval: context.state.endsAt.addingTimeInterval(
                                    -BlobSurface.sessionDuration)...context.state.endsAt, countsDown: true
                            )
                            .font(.caption2.monospacedDigit()).frame(width: 46)
                            .accessibilityLabel("Companion time remaining")
                        }
                    }
                    .fontDesign(.rounded).padding(.bottom, 2)
                }
            } compactLeading: {
                IslandBlob(seed: context.attributes.seed, pulse: context.state.pulse).frame(
                    width: 28, height: 28)
            } compactTrailing: {
                if context.state.signal.mode == .off {
                    Image(systemName: "sparkles").foregroundStyle(.mint).accessibilityLabel("Blob companion")
                } else {
                    SignalBars(levels: levels(context), compact: true).frame(height: 20)
                        .accessibilityHidden(false).accessibilityLabel(title(context))
                }
            } minimal: {
                IslandBlob(seed: context.attributes.seed, pulse: context.state.pulse).frame(
                    width: 24, height: 24)
            }
            .widgetURL(BlobSurface.townURL)
            .keylineTint(.mint)
        }
    }

    private func title(_ context: ActivityViewContext<BlobCompanionAttributes>) -> String {
        if context.isStale {
            return Date() >= context.state.endsAt ? "Time to rest." : "No recent signal"
        }
        return context.state.signal.title
    }

    private var waveButton: some View {
        Button(intent: WaveBlobIntent()) {
            Image(systemName: "hand.wave.fill")
                .font(.system(size: 15, weight: .semibold))
                .frame(width: 44, height: 44)
                .background(.white.opacity(0.09), in: Circle())
        }
        .buttonStyle(.plain).foregroundStyle(.mint)
        .accessibilityLabel("Say hello to your blob")
    }

    private func levels(_ context: ActivityViewContext<BlobCompanionAttributes>) -> [Int] {
        context.isStale ? [] : context.state.signal.sample.levels
    }
}

private struct IslandBlob: View {
    let seed: String
    let pulse: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        BlobGlyph(seed: seed)
            .scaleEffect(
                x: reduceMotion ? 1 : pulse.isMultiple(of: 2) ? 1.05 : 0.95,
                y: reduceMotion ? 1 : pulse.isMultiple(of: 2) ? 0.95 : 1.05
            )
            .rotationEffect(.degrees(reduceMotion ? 0 : pulse.isMultiple(of: 2) ? -6 : 6))
            .animation(reduceMotion ? nil : .spring(response: 0.8, dampingFraction: 0.5), value: pulse)
    }
}

#Preview("Lock Screen", as: .content, using: BlobCompanionAttributes(seed: BlobSurface.previewSeed)) {
    BlobCompanionLiveActivity()
} contentStates: {
    BlobCompanionAttributes.ContentState(endsAt: .now.addingTimeInterval(3600))
    BlobCompanionAttributes.ContentState(
        endsAt: .now.addingTimeInterval(3600),
        signal: .init(
            mode: .receiving, sample: .init(levels: [1, 1, 2, 3, 2, 3, 4, 3, 4], observedAt: .now)), pulse: 1)
}

#Preview(
    "Compact", as: .dynamicIsland(.compact), using: BlobCompanionAttributes(seed: BlobSurface.previewSeed)
) {
    BlobCompanionLiveActivity()
} contentStates: {
    BlobCompanionAttributes.ContentState(
        endsAt: .now.addingTimeInterval(3600),
        signal: .init(mode: .receiving, sample: .init(levels: [1, 2, 3, 4, 3], observedAt: .now)), pulse: 1)
}

#Preview(
    "Expanded", as: .dynamicIsland(.expanded), using: BlobCompanionAttributes(seed: BlobSurface.previewSeed)
) {
    BlobCompanionLiveActivity()
} contentStates: {
    BlobCompanionAttributes.ContentState(
        endsAt: .now.addingTimeInterval(3600),
        signal: .init(
            mode: .receiving, sample: .init(levels: [1, 1, 2, 3, 2, 3, 4, 3, 4], observedAt: .now)), pulse: 1)
}
