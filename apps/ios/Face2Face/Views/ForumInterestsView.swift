import Face2FaceCore
import SwiftUI

/// The account page's picker, reached from the notice board with the same catalog and rules.
struct ForumInterestsView: View {
    let context: ForumContext
    let onSaved: () -> Void
    @State private var model: InterestsModel
    @Environment(\.dismiss) private var dismiss

    init(context: ForumContext, session: SessionModel, onSaved: @escaping () -> Void) {
        self.context = context
        self.onSaved = onSaved
        _model = State(
            initialValue: InterestsModel(
                session: session, repository: { try await context.repository() },
                onSaved: { context.revision += 1 }))
    }
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Your Interests").font(.headline)
                Spacer()
                Button("Done") {
                    dismiss()
                }
                .font(.subheadline.weight(.bold)).frame(minWidth: 44, minHeight: 44)
                .disabled(model.isSaving || model.isAdding)
                .accessibilityIdentifier("forumInterestsDone")
            }.padding(.horizontal, 24).padding(.top, 12)
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Find your little circles.").font(.title2.weight(.bold))
                    Text("These are the same interests as on your account page. Changes save as you pick.")
                        .font(.subheadline).foregroundStyle(MeadowPalette.secondaryInk)
                    Text(
                        "New interests open a forum when three people choose them. Members can see hosts and attendees. Removing an interest hides its forum but keeps existing RSVPs."
                    )
                    .font(.footnote).foregroundStyle(MeadowPalette.secondaryInk)
                    if context.isPreview { ForumPreviewLabel() }
                    MeadowCard { InterestsSection(model: model) }
                }.padding(24).frame(maxWidth: 560).frame(maxWidth: .infinity)
            }.scrollDismissesKeyboard(.interactively)
        }
        .foregroundStyle(MeadowPalette.ink).fontDesign(.rounded)
        .background(MeadowPalette.grass.ignoresSafeArea())
        .interactiveDismissDisabled(model.isSaving || model.isAdding)
        .onDisappear {
            context.revision += 1
            onSaved()
        }
    }
}
