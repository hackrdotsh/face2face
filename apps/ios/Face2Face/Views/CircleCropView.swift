import Face2FaceCore
import SwiftUI

/// Lets the person pan and zoom a photo under a circle, then hands back the square around it.
struct CircleCropView: View {
    let image: UIImage
    let onUse: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var crop: PhotoCrop?
    @State private var gestureStart: PhotoCrop?

    private static let gutter: CGFloat = 24

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                GeometryReader { geometry in
                    let side = min(geometry.size.width, geometry.size.height) - Self.gutter * 2
                    viewport(side: side)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .onAppear { crop = PhotoCrop(imageSize: image.size, viewportSide: side) }
                }
                if let crop {
                    Slider(value: zoomBinding(crop), in: 1...PhotoCrop.maxZoom) { Text("Zoom") }
                        .padding(.horizontal, Self.gutter)
                }
            }
            .padding(.bottom, 24)
            .background(Color.black)
            .navigationTitle("Move and Scale")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Use photo") {
                        guard let crop else { return }
                        onUse(croppedImage(crop))
                        dismiss()
                    }
                    .disabled(crop == nil)
                }
            }
        }
    }

    private func viewport(side: CGFloat) -> some View {
        Color.clear
            .frame(width: side, height: side)
            .overlay {
                if let crop {
                    Image(uiImage: image)
                        .resizable()
                        .frame(width: crop.displayedSize.width, height: crop.displayedSize.height)
                        .offset(crop.offset)
                }
            }
            .overlay {
                CircleHole().fill(.black.opacity(0.55), style: FillStyle(eoFill: true))
                Circle().strokeBorder(.white.opacity(0.8), lineWidth: 1)
            }
            .clipped()
            .contentShape(Rectangle())
            .gesture(panAndZoom)
            .accessibilityElement()
            .accessibilityLabel("Photo crop. Drag to move, pinch to zoom.")
    }

    private var panAndZoom: some Gesture {
        DragGesture(minimumDistance: 0)
            .simultaneously(with: MagnifyGesture())
            .onChanged { value in
                guard let start = gestureStart ?? crop else { return }
                gestureStart = start
                let translation = value.first?.translation ?? .zero
                var moved = start
                moved.move(
                    zoom: start.zoom * (value.second?.magnification ?? 1),
                    offset: CGSize(
                        width: start.offset.width + translation.width,
                        height: start.offset.height + translation.height))
                crop = moved
            }
            .onEnded { _ in gestureStart = nil }
    }

    private func zoomBinding(_ current: PhotoCrop) -> Binding<CGFloat> {
        Binding(
            get: { crop?.zoom ?? 1 },
            set: { zoom in
                var moved = crop ?? current
                moved.move(zoom: zoom, offset: moved.offset)
                crop = moved
            })
    }

    /// Draws the square under the viewport at full resolution, upright.
    private func croppedImage(_ crop: PhotoCrop) -> UIImage {
        let source = crop.sourceRect
        let side = crop.outputSide(pixelsPerPoint: image.scale)
        let pointsToOutput = side / source.width
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).image { _ in
            image.draw(
                in: CGRect(
                    x: -source.minX * pointsToOutput, y: -source.minY * pointsToOutput,
                    width: image.size.width * pointsToOutput, height: image.size.height * pointsToOutput))
        }
    }
}

/// The viewport with the crop circle cut out, for an even-odd fill.
private struct CircleHole: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path(rect)
        path.addEllipse(in: rect)
        return path
    }
}
