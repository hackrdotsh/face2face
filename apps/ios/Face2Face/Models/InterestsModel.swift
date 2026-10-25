import Face2FaceCore
import Foundation
import Observation

/// The signed-in person's interests. Taps change the picks right away and save in the
/// background, one request at a time, so quick taps never race each other.
@MainActor
@Observable
final class InterestsModel {
    var query = ""
    private(set) var isLoading = false
    private(set) var isSaving = false
    private(set) var isAdding = false
    private(set) var loadFailed = false
    var errorMessage: String?

    /// The last catalog the server confirmed.
    private var saved: InterestCatalog?
    /// The picks on screen, which run ahead of `saved` while a save is in flight.
    private var selectedIDs: Set<String> = []
    private var saveTask: Task<Void, Never>?
    private var saveFailed = false
    private let session: SessionModel

    init(session: SessionModel) {
        self.session = session
    }

    /// The catalog as it looks with the on-screen picks, with member counts to match.
    var catalog: InterestCatalog? {
        guard let saved else { return nil }
        return InterestCatalog(
            maxSelected: saved.maxSelected,
            interests: saved.interests.map { choice in
                let selected = selectedIDs.contains(choice.id)
                let change = (selected ? 1 : 0) - (choice.selected ? 1 : 0)
                return InterestChoice(
                    id: choice.id, name: choice.name, memberCount: max(0, choice.memberCount + change),
                    selected: selected)
            })
    }

    /// Unpicked interests ranked for the query.
    var suggestions: [InterestChoice] {
        catalog?.ranked(for: query).filter { !$0.selected } ?? []
    }

    /// The normalized query when it can become a new interest, or nil when it matches one already.
    var newInterestName: String? {
        let name = InterestName.normalize(query)
        guard InterestName.isValid(name), catalog?.exactMatch(for: name) == nil else { return nil }
        return name
    }

    func load() async {
        guard saved == nil, !isLoading else { return }
        if session.isTownPreview {
            apply(Self.preview)
            return
        }
        isLoading = true
        loadFailed = false
        defer { isLoading = false }
        do {
            apply(try await session.client().interests())
        } catch {
            loadFailed = true
            errorMessage = error.localizedDescription
        }
    }

    func toggle(_ choice: InterestChoice) {
        guard let catalog, !isAdding else { return }
        errorMessage = nil
        if selectedIDs.contains(choice.id) {
            selectedIDs.remove(choice.id)
        } else {
            guard !catalog.isFull else {
                errorMessage = APIError.interestLimitReached.localizedDescription
                return
            }
            selectedIDs.insert(choice.id)
        }
        if saveTask == nil {
            saveTask = Task {
                await save()
                saveTask = nil
            }
        }
    }

    /// Picks the interest the query names, creating it when it is new.
    func submitQuery() async {
        if let match = catalog?.exactMatch(for: query) {
            if !match.selected { toggle(match) }
            query = ""
        } else if let name = newInterestName {
            await add(name)
        }
    }

    func add(_ name: String) async {
        guard !isAdding, !isSaving else { return }
        isAdding = true
        errorMessage = nil
        defer { isAdding = false }
        do {
            apply(try await session.client().addInterest(named: name))
            query = ""
        } catch APIError.invalidFields(let fields) {
            errorMessage = fields["name"] ?? APIError.invalidFields(fields).localizedDescription
        } catch APIError.rateLimited {
            errorMessage = "You've added 5 new interests today. Try again tomorrow."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Waits for picks still being saved. Returns false when the last save failed.
    func finishSaving() async -> Bool {
        await saveTask?.value
        return !saveFailed
    }

    private func save() async {
        guard !isSaving else { return }
        isSaving = true
        defer { isSaving = false }
        saveFailed = false
        while let saved, selectedIDs != Set(saved.selected.map(\.id)) {
            let wanted = selectedIDs
            do {
                let result = try await session.client().replaceInterests(wanted.sorted())
                self.saved = result
            } catch {
                selectedIDs = Set(saved.selected.map(\.id))
                saveFailed = true
                errorMessage = error.localizedDescription
                return
            }
        }
    }

    private func apply(_ catalog: InterestCatalog) {
        saved = catalog
        selectedIDs = Set(catalog.selected.map(\.id))
    }

    private static let preview = InterestCatalog(
        maxSelected: 10,
        interests: [
            ("coffee", 42, true), ("hiking", 31, true), ("board games", 18, false), ("jazz", 12, false),
            ("film", 27, false), ("climbing", 9, false), ("live music", 22, false),
        ].map { InterestChoice(id: $0.0, name: $0.0, memberCount: $0.1, selected: $0.2) })
}
