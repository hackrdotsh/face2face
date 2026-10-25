import Face2FaceCore
import SwiftUI

struct ForumEditorView: View {
    let context: ForumContext
    let forums: [TownForum]
    let post: ForumPost?
    let onSaved: (ForumPost) -> Void
    @State private var forumID: String
    @State private var title: String
    @State private var details: String
    @State private var location: String
    @State private var starts: Date
    @State private var ends: Date
    @State private var hasEnd: Bool
    @State private var saving = false
    @State private var error: String?
    @State private var confirmDiscard = false
    private let original: ForumPostInput
    private let originalForumID: String
    @Environment(\.dismiss) private var dismiss

    init(
        context: ForumContext, forums: [TownForum], forumID: String?, post: ForumPost?,
        onSaved: @escaping (ForumPost) -> Void
    ) {
        self.context = context
        self.forums = forums
        self.post = post
        self.onSaved = onSaved
        let start = post?.startDate ?? Date().addingTimeInterval(3600)
        let end = post?.endDate ?? start.addingTimeInterval(3600)
        let id = post?.forumId ?? forumID ?? forums.first?.id ?? ""
        _forumID = State(initialValue: id)
        originalForumID = id
        _title = State(initialValue: post?.title ?? "")
        _details = State(initialValue: post?.description ?? "")
        _location = State(initialValue: post?.location ?? "")
        _starts = State(initialValue: start)
        _ends = State(initialValue: end)
        _hasEnd = State(initialValue: post?.endsAt != nil)
        original = ForumPostInput(
            title: post?.title ?? "", description: post?.description,
            location: post?.location, startsAt: start, endsAt: post?.endDate)
    }

    private var input: ForumPostInput {
        ForumPostInput(
            title: title, description: details, location: location, startsAt: starts,
            endsAt: hasEnd ? ends : nil)
    }
    private var dirty: Bool { input != original || forumID != originalForumID }
    var body: some View {
        VStack(spacing: 0) {
            ForumBar(
                title: post == nil ? "Pin a new plan" : "Edit event", backLabel: "Cancel event editing",
                back: {
                    if dirty { confirmDiscard = true } else { dismiss() }
                }
            ) {
                Button(post == nil ? "Post" : "Save") { Task { await save() } }
                    .font(.subheadline.weight(.bold)).frame(minWidth: 44, minHeight: 44)
                    .disabled(saving || forumID.isEmpty || !input.validationErrors.isEmpty)
                    .accessibilityIdentifier("forumEventSave")
            }
            .disabled(saving)
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("A little reason to get together.").font(.title2.weight(.bold))
                    Text(
                        "Your name and profile avatar will be shown to members of this interest. Only share a place you're comfortable posting."
                    )
                    .font(.footnote).foregroundStyle(MeadowPalette.secondaryInk)
                    if context.isPreview { ForumPreviewLabel() }
                    if let error {
                        Text(error).foregroundStyle(MeadowPalette.errorInk).font(.subheadline)
                            .accessibilityIdentifier("forumEditorError")
                    }
                    VStack(alignment: .leading, spacing: 16) {
                        if post == nil && !forums.isEmpty {
                            Picker("Forum", selection: $forumID) {
                                ForEach(forums) { forum in Text(forum.interestName.capitalized).tag(forum.id)
                                }
                            }.accessibilityIdentifier("forumEventForum")
                        }
                        Text("What's the plan?").font(.headline)
                        TextField("Give it a title", text: $title)
                            .padding(14).background(
                                MeadowPalette.field, in: RoundedRectangle(cornerRadius: 14)
                            )
                            .accessibilityIdentifier("forumEventTitle")
                        fieldError("title", showing: !title.isEmpty)
                        Text("Tell them a little more").font(.headline)
                        TextField("What should people know? (optional)", text: $details, axis: .vertical)
                            .lineLimit(3...8).padding(14).background(
                                MeadowPalette.field, in: RoundedRectangle(cornerRadius: 14)
                            )
                            .accessibilityIdentifier("forumEventDescription")
                        fieldError("description")
                        Text("A place to meet").font(.headline)
                        TextField("Place or meeting point (optional)", text: $location)
                            .padding(14).background(
                                MeadowPalette.field, in: RoundedRectangle(cornerRadius: 14)
                            )
                            .accessibilityIdentifier("forumEventLocation")
                        fieldError("location")
                    }.padding(20).background(MeadowPalette.paper, in: RoundedRectangle(cornerRadius: 24))
                    VStack(alignment: .leading, spacing: 18) {
                        DatePicker(
                            "Starts", selection: $starts, displayedComponents: [.date, .hourAndMinute]
                        )
                        .accessibilityIdentifier("forumEventStarts")
                        Toggle("Include an end time", isOn: $hasEnd).accessibilityIdentifier(
                            "forumEventHasEnd")
                        if hasEnd {
                            DatePicker(
                                "Ends", selection: $ends, displayedComponents: [.date, .hourAndMinute]
                            )
                            .accessibilityIdentifier("forumEventEnds")
                            fieldError("endsAt")
                        }
                        Text(
                            "Times are shown in \(TimeZone.current.localizedName(for: .generic, locale: .current) ?? TimeZone.current.identifier)."
                        )
                        .font(.caption).foregroundStyle(MeadowPalette.secondaryInk)
                    }.padding(20).background(MeadowPalette.paper, in: RoundedRectangle(cornerRadius: 24))
                    if saving { ProgressView("Pinning your plan…").frame(maxWidth: .infinity) }
                }.padding(24).frame(maxWidth: 560).frame(maxWidth: .infinity).disabled(saving)
            }.scrollDismissesKeyboard(.interactively)
        }
        .foregroundStyle(MeadowPalette.ink).fontDesign(.rounded)
        .tint(MeadowPalette.accentShadow).background(MeadowPalette.grass.ignoresSafeArea())
        .interactiveDismissDisabled(dirty || saving)
        .onChange(of: hasEnd) { if hasEnd && ends < starts { ends = starts.addingTimeInterval(3600) } }
        .confirmationDialog("Discard this draft?", isPresented: $confirmDiscard, titleVisibility: .visible) {
            Button("Discard draft", role: .destructive) { dismiss() }
            Button("Keep editing", role: .cancel) {}
        }
    }
    @ViewBuilder private func fieldError(_ field: String, showing: Bool = true) -> some View {
        if showing, let error = input.validationErrors[field] {
            Text(error).font(.caption).foregroundStyle(MeadowPalette.errorInk)
        }
    }
    @MainActor private func save() async {
        guard !saving, input.validationErrors.isEmpty else { return }
        saving = true
        error = nil
        defer { saving = false }
        do {
            let source = try await context.repository()
            let result: ForumPost
            if let post {
                result = try await source.updateForumPost(post.id, input: input)
            } else {
                result = try await source.createForumPost(forumID: forumID, input: input)
            }
            try Task.checkCancellation()
            context.revision += 1
            onSaved(result)
            dismiss()
        } catch {
            guard !Task.isCancelled else { return }
            self.error =
                error is URLError
                ? "Couldn't confirm whether it saved. Check the forum before trying again."
                : ForumContext.message(error)
        }
    }
}
