import RealityKit
import SwiftUI

struct MeadowScene: View {
    @AppStorage("forest3DEnabled") private var enabled = true
    var isMoving: Bool
    var encounterBottomInset: CGFloat

    var body: some View {
        Group {
            if #available(iOS 18.0, *), enabled {
                Forest3DView(isMoving: isMoving, bottomInset: encounterBottomInset)
            } else {
                MeadowCanvasScene(isMoving: isMoving, encounterBottomInset: encounterBottomInset)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

@available(iOS 18.0, *)
private struct Forest3DView: View {
    let isMoving: Bool
    let bottomInset: CGFloat
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var world: Forest3DWorld?
    @State private var failed = false

    private var running: Bool { isMoving && !reduceMotion && scenePhase == .active && previewTime == nil }

    private var previewTime: Double? {
        #if DEBUG
            let arguments = ProcessInfo.processInfo.arguments
            if let index = arguments.firstIndex(of: "-forest-preview-time"),
                arguments.indices.contains(index + 1),
                let time = Double(arguments[index + 1]), time.isFinite, time >= 0
            {
                return time
            }
        #endif
        return nil
    }

    var body: some View {
        GeometryReader { geometry in
            if failed {
                MeadowCanvasScene(isMoving: isMoving, encounterBottomInset: bottomInset)
            } else {
                RealityView { content in
                    do {
                        let world = try Forest3DWorld(initialTime: previewTime ?? 0)
                        world.configure(
                            dark: colorScheme == .dark, viewport: geometry.size, bottomInset: bottomInset)
                        content.camera = .virtual
                        content.add(world.root)
                        self.world = world
                    } catch {
                        print("3D forest unavailable: \(error)")
                        failed = true
                    }
                } update: { _ in
                    world?.configure(
                        dark: colorScheme == .dark, viewport: geometry.size, bottomInset: bottomInset)
                } placeholder: {
                    MeadowCanvasScene(isMoving: false, encounterBottomInset: bottomInset)
                }
                .task(id: running) {
                    guard running else { return }
                    var previous = ProcessInfo.processInfo.systemUptime
                    while !Task.isCancelled {
                        do { try await Task.sleep(for: .milliseconds(33)) } catch { return }
                        let now = ProcessInfo.processInfo.systemUptime
                        world?.update(delta: now - previous)
                        previous = now
                    }
                }
            }
        }
        .background(MeadowPalette.grass)
        .overlay(alignment: .top) {
            LinearGradient(
                colors: [MeadowPalette.grass, MeadowPalette.grass.opacity(0)], startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 230)
        }
    }
}
