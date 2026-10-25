import Face2FaceCore
import PhotosUI
import SwiftUI

/// Shows the current photo or blob, and lets the person pick, crop, or remove a photo.
struct ProfilePhotoEditor: View {
    let avatar: Avatar
    private let session: SessionModel
    @State private var model: ProfilePhotoModel
    @State private var pickerItem: PhotosPickerItem?
    @State private var picked: PickedPhoto?

    init(avatar: Avatar, session: SessionModel) {
        self.avatar = avatar
        self.session = session
        _model = State(initialValue: ProfilePhotoModel(session: session))
    }

    var body: some View {
        HStack(spacing: 16) {
            AvatarView(avatar: avatar, session: session, side: 72)
            VStack(alignment: .leading, spacing: 8) {
                PhotosPicker(
                    avatar.photo == nil ? "Choose a photo" : "Change photo", selection: $pickerItem,
                    matching: .images)
                if avatar.photo != nil {
                    Button("Remove photo", role: .destructive) { Task { await model.remove() } }
                }
            }
            .buttonStyle(.borderless)
        }
        .disabled(model.activity.isBusy)
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            pickerItem = nil
            Task { await open(item) }
        }
        .sheet(item: $picked) { photo in
            CircleCropView(image: photo.image) { cropped in Task { await model.upload(cropped) } }
        }
        .activityAlert(model.activity)
    }

    private func open(_ item: PhotosPickerItem) async {
        await model.activity.run {
            guard let data = try await item.loadTransferable(type: Data.self), let image = UIImage(data: data)
            else { throw PhotoError.unreadable }
            picked = PickedPhoto(image: image)
        }
    }
}

private struct PickedPhoto: Identifiable {
    let id = UUID()
    let image: UIImage
}
