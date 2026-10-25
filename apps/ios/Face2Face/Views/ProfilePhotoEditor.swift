import Face2FaceCore
import PhotosUI
import SwiftUI

/// Shows the current photo or blob, and lets the person pick, crop, or remove a photo.
struct ProfilePhotoEditor: View {
    let avatar: Avatar
    private let session: SessionModel
    /// A large centered avatar with buttons below it, for the onboarding step.
    private let prominent: Bool
    @State private var model: ProfilePhotoModel
    @State private var pickerItem: PhotosPickerItem?
    @State private var picked: PickedPhoto?

    init(avatar: Avatar, session: SessionModel, prominent: Bool = false) {
        self.avatar = avatar
        self.session = session
        self.prominent = prominent
        _model = State(initialValue: ProfilePhotoModel(session: session))
    }

    var body: some View {
        layout
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

    @ViewBuilder private var layout: some View {
        if prominent {
            VStack(spacing: 16) {
                AvatarView(avatar: avatar, session: session, side: 136)
                    .overlay {
                        if model.activity.isBusy { ProgressView().tint(MeadowPalette.ink) }
                    }
                HStack(spacing: 20) { actions }
                    .font(.system(.subheadline, design: .rounded, weight: .bold))
                    .foregroundStyle(MeadowPalette.ink)
                    .frame(minHeight: 44)
            }
        } else {
            HStack(spacing: 16) {
                AvatarView(avatar: avatar, session: session, side: 72)
                VStack(alignment: .leading, spacing: 8) { actions }
                    .buttonStyle(.borderless)
            }
        }
    }

    @ViewBuilder private var actions: some View {
        PhotosPicker(selection: $pickerItem, matching: .images) {
            Text(avatar.photo == nil ? "Choose a Photo" : "Change Photo").underline()
        }
        if avatar.photo != nil {
            Button(role: .destructive) {
                Task { await model.remove() }
            } label: {
                Text("Remove Photo").underline()
            }
        }
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
