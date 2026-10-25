import Face2FaceCore
import Foundation
import Observation

/// Edits the signed-in person's status, then reloads the account to show it.
@MainActor
@Observable
final class StatusMessageModel {
    let activity = Activity()
    var draft: String

    private let session: SessionModel
    private var saved: String?

    init(session: SessionModel, saved: String?) {
        self.session = session
        self.saved = saved
        draft = saved ?? ""
    }

    var length: Int { StatusMessage.normalized(draft)?.unicodeScalars.count ?? 0 }
    var isTooLong: Bool { StatusMessage.isTooLong(draft) }
    var hasChanges: Bool { StatusMessage.normalized(draft) != saved }
    var canSave: Bool { hasChanges && !isTooLong && !activity.isBusy }

    func save() async {
        await activity.run {
            let statusMessage = try await self.session.client().updateStatusMessage(
                StatusMessage.normalized(self.draft))
            self.saved = statusMessage
            self.draft = statusMessage ?? ""
            try await self.session.refreshAccount()
        }
    }

    func clear() async {
        draft = ""
        guard hasChanges else { return }
        await save()
    }
}
