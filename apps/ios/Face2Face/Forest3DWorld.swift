import RealityKit
import SwiftUI
import UIKit
import simd

/// Finite, repeating scenery. These blobs never represent nearby accounts or encounters.
@available(iOS 18.0, *)
@MainActor
final class Forest3DWorld {
    let root = Entity()
    let camera = Entity()
    private let landscape = Entity()
    private let keyLight = DirectionalLight()
    private let fillLight = DirectionalLight()
    private let blobs: [Forest3DAssets.Blob]
    private var fireflies: [Entity] = []
    private var isDark: Bool?
    private var elapsed = 0.0
    private var viewport = CGSize(width: 420, height: 900)
    private var bottomInset: CGFloat = 130

    init() throws {
        root.name = "forest-world"
        landscape.name = "landscape"
        root.addChild(landscape)
        var lens = OrthographicCameraComponent()
        lens.scale = 14
        lens.scaleDirection = .vertical
        lens.near = 0.1
        lens.far = 120
        camera.components.set(lens)
        root.addChild(camera)

        let ground = ModelEntity(mesh: .generatePlane(width: 100, depth: 200), materials: [SimpleMaterial()])
        ground.name = "grass"
        ground.position.z = -20
        root.addChild(ground)
        for (name, width, height) in [("path-edge", Float(3.1), Float(0.015)), ("path", 2.8, 0.025)] {
            let path = ModelEntity(mesh: try Forest3DAssets.path(width: width), materials: [SimpleMaterial()])
            path.name = name
            path.position.y = height
            landscape.addChild(path)
        }

        let templates = try (0..<3).map { try Forest3DAssets.pine(variant: $0) }
        for tile in -2...1 {
            for row in 0..<10 {
                let z = Float(tile * 32) + Float(row) * 3.2
                for bank in [-1, 1] {
                    for depth in 0..<3 {
                        let seed = row * 13 + depth * 7 + (bank > 0 ? 11 : 0)
                        let tree = templates[seed % templates.count].clone(recursive: true)
                        let stagger = Float(seed % 7) * 0.19
                        tree.position = [
                            Forest3DAssets.pathCenter(z + stagger) + Float(bank)
                                * (2.75 + Float(depth) * 2.05 + Float(seed % 5) * 0.12),
                            0, z + stagger,
                        ]
                        tree.scale = SIMD3(repeating: 0.92 + Float(seed % 5) * 0.08)
                        tree.orientation = simd_quatf(angle: Float(seed) * 0.31, axis: [0, 1, 0])
                        landscape.addChild(tree)
                    }
                }
            }
        }
        blobs = try [
            Forest3DAssets.blob(seed: [1, 1, 24, 29, 130, 216, 96, 190, 118, 230, 102, 32, 118, 190, 128, 48]
            ),
            Forest3DAssets.blob(seed: [
                2, 0, 135, 58, 192, 115, 230, 128, 185, 91, 206, 165, 118, 190, 128, 86,
            ]),
            Forest3DAssets.blob(seed: [
                0, 0, 28, 91, 160, 195, 110, 230, 130, 175, 115, 160, 100, 140, 128, 180,
            ]),
        ]
        for blob in blobs {
            blob.root.scale = SIMD3(repeating: 1.2)
            root.addChild(blob.root)
        }
        keyLight.look(at: .zero, from: [-12, 22, 12], relativeTo: nil)
        keyLight.shadow = .init(shadowProjection: .automatic(maximumDistance: 70), depthBias: 0.1)
        fillLight.look(at: .zero, from: [10, 15, -10], relativeTo: nil)
        root.addChild(keyLight)
        root.addChild(fillLight)
        for index in 0..<16 {
            let light = ModelEntity(
                mesh: .generateSphere(radius: 0.035),
                materials: [UnlitMaterial(color: UIColor(red: 1, green: 0.9, blue: 0.5, alpha: 1))])
            light.name = "firefly"
            light.position = [Float(index % 4 - 2) * 2.4, 0.65, Float(index * 3) - 28]
            root.addChild(light)
            fireflies.append(light)
        }
        configure(dark: false, viewport: viewport, bottomInset: bottomInset)
        update(delta: 0)
    }

    func configure(dark: Bool, viewport: CGSize, bottomInset: CGFloat) {
        self.viewport = viewport
        self.bottomInset = bottomInset
        if isDark != dark {
            isDark = dark
            paint(root, dark: dark)
            keyLight.light.color = dark ? UIColor(red: 0.7, green: 0.77, blue: 1, alpha: 1) : .white
            keyLight.light.intensity = dark ? 650 : 2_000
            fillLight.light.intensity = dark ? 140 : 650
            for firefly in fireflies { firefly.isEnabled = dark }
        }
        positionCamera()
    }

    func update(delta: Double) {
        guard delta.isFinite else { return }
        elapsed += min(max(delta, 0), 0.1)
        let scroll = Float(elapsed * 0.65).truncatingRemainder(dividingBy: 32)
        landscape.position.z = scroll
        for (index, blob) in blobs.enumerated() {
            let z: Float =
                index == 0
                ? 4 : -22 + (Float(elapsed * 0.95) + Float(index * 13)).truncatingRemainder(dividingBy: 34)
            let lane: Float = index == 0 ? -0.65 : 0.65
            blob.root.position = [Forest3DAssets.pathCenter(z - scroll) + lane, 0, z]
            blob.pose(at: elapsed + Double(index))
        }
        for (index, light) in fireflies.enumerated() {
            light.position.y = 0.6 + Float(sin(elapsed * 0.9 + Double(index))) * 0.25
        }
        positionCamera()
    }

    private func positionCamera() {
        let fraction = Float(min(0.88, max(0.65, 1 - bottomInset / max(1, viewport.height))))
        let targetZ = 4 - (fraction - 0.5) * 28 / 0.65
        let x = blobs.first?.root.position.x ?? 0
        camera.look(at: [x, 0, targetZ], from: [x, 24, targetZ + 28], relativeTo: nil)
    }

    private func paint(_ entity: Entity, dark: Bool) {
        let color: UIColor?
        switch entity.name {
        case "grass": color = dark ? hex(0x172D2E) : hex(0xC8DDB2)
        case "path": color = dark ? hex(0x526162) : hex(0xF1DFB4)
        case "path-edge": color = dark ? hex(0x364D49) : hex(0xBCBD91)
        case "trunk": color = dark ? hex(0x62524B) : hex(0x8F6D52)
        case "leaves-0": color = dark ? hex(0x254A43) : hex(0x508C59)
        case "leaves-1": color = dark ? hex(0x2D5850) : hex(0x659E65)
        case "leaves-2": color = dark ? hex(0x356354) : hex(0x7BB376)
        default: color = nil
        }
        if let color, let model = entity as? ModelEntity {
            model.model?.materials = [SimpleMaterial(color: color, roughness: 1, isMetallic: false)]
        }
        for child in entity.children { paint(child, dark: dark) }
    }

    private func hex(_ value: UInt32) -> UIColor {
        UIColor(
            red: Double((value >> 16) & 255) / 255, green: Double((value >> 8) & 255) / 255,
            blue: Double(value & 255) / 255, alpha: 1)
    }
}
