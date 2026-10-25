import Face2FaceCore
import SwiftUI

struct BlobCompanionSection: View {
    let seed: String?
    @State private var model = BlobCompanionModel.shared

    var body: some View {
        Section {
            BlobCompanionPreview(seed: seed ?? BlobSurface.previewSeed, isEnabled: model.isEnabled)
                .frame(maxWidth: .infinity)
                .listRowBackground(Color.clear)
            Toggle(
                "Blob in Dynamic Island",
                isOn: Binding(
                    get: { model.isEnabled },
                    set: { enabled in
                        if enabled, let seed { model.start(seed: seed) } else { model.stop() }
                    })
            )
            .disabled(seed == nil)
            .accessibilityIdentifier("blobCompanionToggle")
            if let current = model.session {
                LabeledContent("Rest time") { Text(current.endsAt, style: .time) }
            }
            if let error = model.errorMessage {
                Text(error).foregroundStyle(MeadowPalette.errorInk)
                    .accessibilityIdentifier("blobCompanionError")
            }
            if !model.isAvailable {
                Text("Live Activities are currently disabled in iPhone Settings.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        } header: {
            Text("Blob companion")
        } footer: {
            Text(
                "A little company for one hour. Appears in Dynamic Island on supported iPhones and on the Lock Screen. This does not turn on discovery. Sign in to bring your blob along. iOS controls Island animations and visibility."
            )
        }
        .onAppear { model.refresh(seed: seed) }
    }
}

private struct BlobCompanionPreview: View {
    let seed: String
    let isEnabled: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var wave = 0

    var body: some View {
        VStack(spacing: 12) {
            Button {
                wave += 1
            } label: {
                TimelineView(
                    .animation(minimumInterval: 1.0 / 30, paused: reduceMotion || scenePhase != .active)
                ) { timeline in
                    let time = timeline.date.timeIntervalSinceReferenceDate
                    let reduceMotion = reduceMotion
                    let pose = reduceMotion ? nil : BlobIdleMotion(seed: seed)?.pose(at: time)
                    ZStack {
                        ForEach(0..<3) { index in
                            Circle()
                                .stroke(
                                    MeadowPalette.accent.opacity(0.5 - Double(index) * 0.12), lineWidth: 1.5
                                )
                                .frame(width: CGFloat(84 + index * 30), height: CGFloat(84 + index * 30))
                                .scaleEffect(reduceMotion ? 1 : 1 + 0.04 * sin(time * 1.6 - Double(index)))
                        }
                        Ellipse().fill(.black.opacity(0.08))
                            .frame(width: 58, height: 9).offset(y: 43)
                        BlobGlyph(seed: seed, pose: pose)
                            .frame(width: 96, height: 96)
                            .offset(y: reduceMotion ? 0 : -4 + 4 * sin(time * 1.6))
                            .keyframeAnimator(initialValue: CGFloat.zero, trigger: wave) { content, value in
                                content.offset(y: reduceMotion ? 0 : value)
                                    .rotationEffect(.degrees(reduceMotion ? 0 : Double(value) / 2))
                            } keyframes: { _ in
                                SpringKeyframe(-24, duration: 0.2, spring: .bouncy)
                                SpringKeyframe(0, duration: 0.5, spring: .bouncy)
                            }
                    }
                    .frame(height: 150)
                }
                .frame(maxWidth: .infinity)
                .background(.black.opacity(0.92), in: RoundedRectangle(cornerRadius: 36))
            }
            .buttonStyle(MeadowPressStyle())
            .accessibilityLabel("Say hello to your blob")
            .accessibilityHint("Plays a decorative bounce")
            .accessibilityIdentifier("blobCompanionPreview")
            Text(isEnabled ? "Your little plus-one." : "A little company, wherever you go.")
                .font(.subheadline.weight(.semibold))
                .contentTransition(.opacity)
                .animation(.easeInOut(duration: 0.2), value: isEnabled)
        }
        .padding(.vertical, 8)
    }
}
