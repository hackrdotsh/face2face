import Face2FaceCore
import SwiftUI

struct OnboardingView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let account: Account
    private let session: SessionModel
    @State private var model: OnboardingModel
    @FocusState private var textFocused: Bool

    init(account: Account, session: SessionModel) {
        self.account = account
        self.session = session
        _model = State(initialValue: OnboardingModel(session: session))
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                MeadowScene(
                    isMoving: !textFocused,
                    encounterBottomInset: geometry.safeAreaInsets.bottom + 104
                )
                .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 0) {
                        topBar
                        if let form = Binding($model.form) {
                            card(form: form).padding(.top, 16)
                        } else if model.activity.isBusy {
                            ProgressView().accessibilityLabel("Loading").padding(.top, 48)
                        }
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: 440)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: max(0, geometry.size.height - 44))
                    .padding(.horizontal, 24)
                    .padding(.top, 12)
                    .padding(.bottom, 32)
                }
                .scrollIndicators(.hidden)
                .scrollBounceBehavior(.basedOnSize)
                .scrollDismissesKeyboard(.interactively)
            }
        }
        .foregroundStyle(MeadowPalette.ink)
        .fontDesign(.rounded)
        .disabled(model.activity.isBusy)
        .activityAlert(model.activity)
        .task { await model.load() }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { textFocused = false }
            }
        }
    }

    private var topBar: some View {
        HStack {
            Button {
                textFocused = false
                withAnimation(stepAnimation) { model.back() }
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(.subheadline, weight: .bold))
                    .frame(width: 44, height: 44)
                    .background(MeadowPalette.paper, in: Circle())
            }
            .buttonStyle(MeadowPressStyle())
            .accessibilityLabel("Previous step")
            .opacity(model.step > 0 ? 1 : 0)
            .disabled(model.step == 0)

            Spacer()
            progress
            Spacer()

            Menu {
                Button("Sign out", role: .destructive) { Task { await model.signOut() } }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(.subheadline, weight: .bold))
                    .frame(width: 44, height: 44)
                    .background(MeadowPalette.paper, in: Circle())
            }
            .accessibilityLabel("More")
        }
    }

    private var progress: some View {
        HStack(spacing: 8) {
            ForEach(0..<model.stepCount, id: \.self) { index in
                Capsule()
                    .fill(index <= model.step ? MeadowPalette.ink : MeadowPalette.paper)
                    .frame(width: index == model.step ? 24 : 8, height: 8)
            }
        }
        .animation(stepAnimation, value: model.step)
        .accessibilityElement()
        .accessibilityLabel("Step \(model.step + 1) of \(model.stepCount)")
    }

    private func card(form: Binding<OnboardingForm>) -> some View {
        MeadowCard {
            VStack(alignment: .leading, spacing: 20) {
                if form.wrappedValue.needsAppUpdate {
                    Label(
                        "Update face2face to finish setting up your profile.", systemImage: "arrow.down.app"
                    )
                    .font(.footnote)
                    .foregroundStyle(MeadowPalette.secondaryInk)
                }
                if let field = model.currentField {
                    OnboardingStepView(
                        field: field, form: form, error: model.fieldErrors[field.key],
                        avatar: account.user.avatar, session: session, textFocused: $textFocused,
                        onSubmit: advance
                    )
                    .id(field.key)
                    .transition(stepTransition)
                    footer(for: field)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .animation(stepAnimation, value: model.step)
        }
        .clipped()
    }

    @ViewBuilder private func footer(for field: OnboardingField) -> some View {
        let skippable = !field.required && !hasValue(for: field)
        MeadowPrimaryButton(
            title: skippable ? "Skip for Now" : (model.isLastStep ? "Finish" : "Next"),
            symbol: model.isLastStep ? "checkmark" : "arrow.right",
            isBusy: model.activity.isBusy,
            action: advance
        )
        .disabled(!model.canContinue)
        .opacity(model.canContinue ? 1 : 0.5)
        .accessibilityIdentifier("onboardingNext")
    }

    private func hasValue(for field: OnboardingField) -> Bool {
        if field.type == .image { return account.user.avatar.photo != nil }
        return model.form?.values()[field.key] != nil
    }

    private func advance() {
        guard model.canContinue else { return }
        textFocused = false
        Task {
            let step = model.step
            await model.next()
            if model.step != step {
                AccessibilityNotification.Announcement("Step \(model.step + 1) of \(model.stepCount)").post()
            }
        }
    }

    private var stepAnimation: Animation {
        reduceMotion ? .easeInOut(duration: 0.15) : .spring(response: 0.4, dampingFraction: 0.86)
    }

    private var stepTransition: AnyTransition {
        if reduceMotion { return .opacity }
        return .asymmetric(
            insertion: .move(edge: model.movedForward ? .trailing : .leading).combined(with: .opacity),
            removal: .move(edge: model.movedForward ? .leading : .trailing).combined(with: .opacity))
    }
}
