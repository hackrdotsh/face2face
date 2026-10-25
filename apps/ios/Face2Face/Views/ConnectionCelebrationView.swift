import Face2FaceCore
import SwiftUI

extension View {
    func connectionCelebrations(_ model: ConnectionCelebrations, available: Bool = true) -> some View {
        modifier(ConnectionCelebrationPresenter(model: model, available: available))
    }
}

private struct ConnectionCelebrationPresenter: ViewModifier {
    let model: ConnectionCelebrations
    let available: Bool
    @Environment(\.scenePhase) private var scenePhase
    @State private var owner = UUID()
    @State private var visible: ConnectionCelebrations.Milestone?
    @State private var appeared = false

    func body(content: Content) -> some View {
        ZStack {
            content.allowsHitTesting(visible == nil).accessibilityHidden(visible != nil)
            if let visible {
                ConnectionCelebrationView(event: visible) { dismiss() }
            }
        }
        .onAppear {
            appeared = true
            presentIfReady()
        }
        .onDisappear {
            appeared = false
            dismiss()
        }
        .onChange(of: model.revision) { presentIfReady() }
        .onChange(of: available) { presentIfReady() }
        .onChange(of: scenePhase) { presentIfReady() }
        .onChange(of: model.presented) {
            if model.presented != visible { visible = nil }
        }
    }

    private func presentIfReady() {
        guard appeared, available, scenePhase == .active else {
            dismiss()
            return
        }
        if visible == nil { visible = model.claim(owner: owner) }
    }

    private func dismiss() {
        visible = nil
        model.dismiss(owner: owner)
    }
}

private struct ConnectionCelebrationView: View {
    let event: ConnectionCelebrations.Milestone
    let dismiss: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var arrived = false
    @State private var burst = false
    @AccessibilityFocusState private var titleFocused: Bool
    private var isPublic: Bool { event.kind == .publicProfiles }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black.opacity(0.28).ignoresSafeArea()
                ViewThatFits(in: .vertical) {
                    card
                    ScrollView { card }.scrollBounceBehavior(.basedOnSize)
                }
                .frame(maxHeight: geometry.size.height)
                .scaleEffect(reduceMotion || arrived ? 1 : 0.92)
                .opacity(arrived ? 1 : 0)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("connectionCelebration")
            }
        }
        .foregroundStyle(MeadowPalette.ink).fontDesign(.rounded)
        .accessibilityAction(.escape) { dismiss() }
        .onAppear {
            withAnimation(reduceMotion ? .easeOut(duration: 0.15) : .spring(duration: 0.6, bounce: 0.3)) {
                arrived = true
            }
            if !reduceMotion { withAnimation(.easeOut(duration: 1.1).delay(0.15)) { burst = true } }
            titleFocused = true
        }
    }

    private var card: some View {
        VStack(spacing: 18) {
            artwork.frame(height: 140).accessibilityHidden(true)
            Text(isPublic ? "PROFILES SHARED" : "PRIVATE CHAT READY")
                .font(.caption.weight(.bold)).tracking(2)
                .foregroundStyle(MeadowPalette.secondaryInk)
            Text(isPublic ? "A familiar face!" : "You both said hello!")
                .font(.system(.title, design: .rounded, weight: .bold))
                .accessibilityAddTraits(.isHeader).accessibilityFocused($titleFocused)
                .accessibilityIdentifier("connectionCelebrationTitle")
            Text(
                isPublic
                    ? "You both chose to share profiles. You can now see each other's profiles and appear as friends in your towns."
                    : "Congratulations! You both accepted. Your private chat is ready, and your profiles stay anonymous."
            )
            .font(.subheadline).foregroundStyle(MeadowPalette.secondaryInk)
            Button("Lovely!") { dismiss() }
                .font(.headline).frame(maxWidth: .infinity).frame(minHeight: 48)
                .background(MeadowPalette.accent, in: Capsule())
                .foregroundStyle(MeadowPalette.accentInk)
                .buttonStyle(MeadowPressStyle())
                .accessibilityIdentifier("connectionCelebrationDismiss")
        }
        .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
        .padding(28).frame(maxWidth: 360)
        .background(MeadowPalette.paper, in: RoundedRectangle(cornerRadius: 32))
        .overlay(RoundedRectangle(cornerRadius: 32).strokeBorder(MeadowPalette.glassEdge))
        .shadow(color: .black.opacity(0.12), radius: 24, y: 12)
        .padding(24).frame(maxWidth: .infinity)
    }

    private var artwork: some View {
        ZStack {
            Circle().fill(MeadowPalette.accent.opacity(0.3)).frame(width: 130, height: 130)
            if !reduceMotion {
                ForEach(0..<16) { index in
                    let angle = Double(index) * .pi / 8
                    Capsule().fill(index.isMultiple(of: 2) ? MeadowPalette.accent : MeadowPalette.treeShade)
                        .frame(width: 5, height: 10).rotationEffect(.radians(angle))
                        .offset(x: cos(angle) * (burst ? 120 : 18), y: sin(angle) * (burst ? 85 : 10))
                        .opacity(burst ? 0 : 1)
                }
            }
            HStack(spacing: -8) {
                decorativeBlob(hue: 24).rotationEffect(.degrees(reduceMotion ? 0 : arrived ? 8 : -15))
                    .offset(x: reduceMotion || arrived ? 0 : -30)
                decorativeBlob(hue: 135).rotationEffect(.degrees(reduceMotion ? 0 : arrived ? -8 : 15))
                    .offset(x: reduceMotion || arrived ? 0 : 30)
            }
            Image(systemName: isPublic ? "heart.fill" : "bubble.left.and.bubble.right.fill")
                .font(.system(size: 25, weight: .bold)).foregroundStyle(MeadowPalette.accentInk)
                .padding(12).background(MeadowPalette.paper, in: Circle())
                .offset(y: 43).scaleEffect(reduceMotion || arrived ? 1 : 0.4)
        }
    }

    private func decorativeBlob(hue: UInt8) -> some View {
        // Fixed fictional seeds, never either participant's private avatar.
        let seed: [UInt8] = [1, 1, hue, 29, 130, 216, 96, 190, 118, 230, 102, 32, 118, 190, 128, 48]
        let encoded = Data(seed).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        return AnimatedBlobView(seed: encoded)
            .frame(width: 76, height: 76)
    }
}
