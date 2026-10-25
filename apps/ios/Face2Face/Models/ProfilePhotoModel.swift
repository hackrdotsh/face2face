import Face2FaceCore
import Foundation
import Observation
import UIKit

/// Changes the signed-in person's photo, then reloads the account to show it.
@MainActor
@Observable
final class ProfilePhotoModel {
    let activity = Activity()

    private let session: SessionModel
    private static let jpegQuality: CGFloat = 0.9

    init(session: SessionModel) {
        self.session = session
    }

    func upload(_ photo: UIImage) async {
        await activity.run {
            guard let jpeg = photo.jpegData(compressionQuality: Self.jpegQuality) else {
                throw PhotoError.unreadable
            }
            _ = try await self.session.client().uploadProfilePhoto(jpeg: jpeg)
            try await self.session.refreshAccount()
        }
    }

    func remove() async {
        await activity.run {
            _ = try await self.session.client().removeProfilePhoto()
            try await self.session.refreshAccount()
        }
    }
}

enum PhotoError: LocalizedError {
    case unreadable

    var errorDescription: String? { "This photo can't be opened. Try another one." }
}
