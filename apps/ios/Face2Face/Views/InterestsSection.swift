import Face2FaceCore
import SwiftUI

/// Picks interests with a search that ranks name matches first, then by how many people share them.
struct InterestsSection: View {
    @Bindable var model: InterestsModel
    /// Off where the screen already titles and explains the picker, as in onboarding.
    var showsHeader = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var searchFocused: Bool

    private static let browseLimit = 12
    private static let searchLimit = 24

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if showsHeader {
                MeadowSectionHeader(
                    title: "Interests",
                    detail: model.catalog.map { "\($0.selected.count) of \($0.maxSelected)" })
            }
            if let catalog = model.catalog {
                picks(catalog)
                search
                suggestions(catalog)
            } else if model.loadFailed {
                failure
            } else {
                ProgressView().frame(maxWidth: .infinity, minHeight: 88)
            }
            if let message = model.errorMessage, model.catalog != nil {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(MeadowPalette.errorInk)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("interestsError")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .task { await model.load() }
        .onChange(of: model.errorMessage) { _, message in
            if let message { AccessibilityNotification.Announcement(message).post() }
        }
    }

    @ViewBuilder private func picks(_ catalog: InterestCatalog) -> some View {
        if catalog.selected.isEmpty {
            if showsHeader {
                Text(
                    "Pick what you love. Shared interests open chances to meet and the forums you see in town."
                )
                .font(.subheadline)
                .foregroundStyle(MeadowPalette.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
            }
        } else {
            ChipFlow(spacing: 8) {
                ForEach(catalog.selected) { choice in
                    Button {
                        toggle(choice)
                    } label: {
                        HStack(spacing: 6) {
                            Text(choice.name.capitalized)
                            Image(systemName: "xmark")
                                .font(.caption2.weight(.heavy))
                                .accessibilityHidden(true)
                        }
                        .pill(fill: MeadowPalette.accent, ink: MeadowPalette.accentInk)
                    }
                    .buttonStyle(MeadowPressStyle())
                    .accessibilityLabel(choice.name)
                    .accessibilityHint("Removes it from your interests")
                    .accessibilityAddTraits(.isSelected)
                }
            }
        }
    }

    private var search: some View {
        MeadowField(
            label: "Find or add an interest", symbol: "magnifyingglass",
            accessory: model.query.isEmpty ? nil : ("Clear", { model.query = "" })
        ) {
            TextField("Search interests", text: $model.query)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.done)
                .focused($searchFocused)
                .onSubmit { Task { await model.submitQuery() } }
                .accessibilityIdentifier("interestSearch")
        }
        .focusTarget { searchFocused = true }
    }

    @ViewBuilder private func suggestions(_ catalog: InterestCatalog) -> some View {
        let searching = !InterestName.normalize(model.query).isEmpty
        let results = model.suggestions.prefix(searching ? Self.searchLimit : Self.browseLimit)
        VStack(alignment: .leading, spacing: 10) {
            if !results.isEmpty {
                Text(searching ? "Matches" : "Popular")
                    .font(.system(.caption, design: .rounded, weight: .bold))
                    .foregroundStyle(MeadowPalette.secondaryInk)
            }
            ChipFlow(spacing: 8) {
                if let name = model.newInterestName {
                    Button {
                        Task { await model.add(name) }
                    } label: {
                        HStack(spacing: 6) {
                            if model.isAdding {
                                ProgressView().controlSize(.mini)
                            } else {
                                Image(systemName: "plus").font(.caption.weight(.heavy))
                            }
                            Text("Add “\(name.capitalized)”")
                        }
                        .pill(fill: MeadowPalette.paper, ink: MeadowPalette.ink, dashed: true)
                    }
                    .buttonStyle(MeadowPressStyle())
                    .disabled(catalog.isFull || model.isAdding || model.isSaving)
                    .accessibilityIdentifier("addInterest")
                }
                ForEach(results) { choice in
                    Button {
                        toggle(choice)
                    } label: {
                        HStack(spacing: 6) {
                            Text(choice.name.capitalized)
                            Text(choice.memberCount, format: .number)
                                .foregroundStyle(MeadowPalette.secondaryInk)
                                .monospacedDigit()
                        }
                        .pill(fill: MeadowPalette.field, ink: MeadowPalette.ink)
                    }
                    .buttonStyle(MeadowPressStyle())
                    .disabled(catalog.isFull || model.isAdding)
                    .accessibilityLabel(choice.name)
                    .accessibilityValue(choice.memberCount == 1 ? "1 person" : "\(choice.memberCount) people")
                    .accessibilityHint("Adds it to your interests")
                }
            }
            if searching, results.isEmpty, model.newInterestName == nil {
                Text(
                    InterestName.isValid(InterestName.normalize(model.query))
                        ? "You already picked that one."
                        : "Use 2 to 32 letters, numbers, spaces, &, ', or -."
                )
                .font(.footnote)
                .foregroundStyle(MeadowPalette.secondaryInk)
            } else if catalog.isFull {
                Text("You picked \(catalog.maxSelected). Remove one to add another.")
                    .font(.footnote)
                    .foregroundStyle(MeadowPalette.secondaryInk)
            }
        }
    }

    private var failure: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(model.errorMessage ?? "Interests didn't load.")
                .font(.subheadline)
                .foregroundStyle(MeadowPalette.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                Task { await model.load() }
            } label: {
                Text("Try Again").underline()
            }
            .font(.subheadline.weight(.semibold))
            .frame(minHeight: 44)
        }
    }

    private func toggle(_ choice: InterestChoice) {
        withAnimation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.82)) {
            model.toggle(choice)
        }
    }
}

extension View {
    fileprivate func pill(fill: Color, ink: Color, dashed: Bool = false) -> some View {
        font(.system(.subheadline, design: .rounded, weight: .semibold))
            .foregroundStyle(ink)
            .lineLimit(1)
            .padding(.horizontal, 14)
            .frame(minHeight: 44)
            .background(fill, in: Capsule())
            .overlay {
                Capsule()
                    .strokeBorder(
                        MeadowPalette.fieldBorder,
                        style: StrokeStyle(lineWidth: 1, dash: dashed ? [4, 3] : []))
            }
            .contentShape(Capsule())
    }
}
