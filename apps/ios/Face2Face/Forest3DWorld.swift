import Face2FaceCore
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
    private struct Firefly {
        let entity: Entity
        let origin: SIMD3<Float>
        let phase: Double
    }
    private var fireflies: [Firefly] = []
    private var isDark: Bool?
    private var elapsed = 0.0
    private var viewport = CGSize(width: 420, height: 900)
    private var bottomInset: CGFloat = 130

    init(initialTime: Double = 0) throws {
        elapsed = initialTime.isFinite && initialTime >= 0 ? initialTime : 0
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
        let fireflyMesh = MeshResource.generateSphere(radius: 0.035)
        let fireflyMaterial = UnlitMaterial(color: UIColor(red: 1, green: 0.9, blue: 0.5, alpha: 1))
        for tile in -2...1 {
            for index in 0..<8 {
                let z = Float(tile * 32 + index * 4)
                let bank: Float = index.isMultiple(of: 2) ? -1 : 1
                let origin: SIMD3<Float> = [Forest3DAssets.pathCenter(z) + bank * 2.15, 0.85, z]
                let light = ModelEntity(mesh: fireflyMesh, materials: [fireflyMaterial])
                light.name = "firefly"
                light.position = origin
                landscape.addChild(light)
                fireflies.append(Firefly(entity: light, origin: origin, phase: Double(index) * 1.7))
            }
        }
        configure(dark: false, viewport: viewport, bottomInset: bottomInset)
        update(delta: 0)
    }

    func configure(dark: Bool, viewport: CGSize, bottomInset: CGFloat) {
        self.viewport = viewport
        self.bottomInset = bottomInset
        if isDark != dark {
            isDark = dark
            paint(root, dark: dark, foliage: Forest3DAssets.foliageMaterials(dark: dark))
            keyLight.light.color = dark ? UIColor(red: 0.7, green: 0.77, blue: 1, alpha: 1) : .white
            keyLight.light.intensity = dark ? 650 : 2_000
            fillLight.light.intensity = dark ? 140 : 650
            for firefly in fireflies { firefly.entity.isEnabled = dark }
        }
        positionCamera()
    }

    func update(delta: Double) {
        guard delta.isFinite else { return }
        elapsed += min(max(delta, 0), 0.1)
        let scroll = Float(elapsed * 0.65).truncatingRemainder(dividingBy: 32)
        landscape.position.z = scroll
        let passers = (0..<2).map { ForestPasserPose.at(time: elapsed, slot: $0) }
        let greeting = passers.first { $0.greetingProgress != nil }?.greetingProgress
        for (index, blob) in blobs.enumerated() {
            let z: Float = index == 0 ? 4 : passers[index - 1].z
            let progress = index == 0 ? greeting : passers[index - 1].greetingProgress
            let hello = progress.map { Float(sin($0 * .pi)) } ?? 0
            let lane: Float = (index == 0 ? -1 : 1) * (0.65 + hello * 0.25)
            blob.root.position = [Forest3DAssets.pathCenter(z - scroll) + lane, 0, z]
            blob.pose(
                at: elapsed + Double(index), greetingProgress: progress,
                facing: index == 0 ? 1 : -1, walkingAway: index == 0)
        }
        for light in fireflies {
            light.entity.position =
                light.origin + [
                    Float(sin(elapsed * 0.4 + light.phase)) * 0.18,
                    Float(sin(elapsed * 0.9 + light.phase)) * 0.25,
                    Float(cos(elapsed * 0.5 + light.phase)) * 0.15,
                ]
        }
        positionCamera()
    }

    private func positionCamera() {
        let fraction = Float(min(0.88, max(0.65, 1 - bottomInset / max(1, viewport.height))))
        let targetZ = 4 - (fraction - 0.5) * 28 / 0.65
        let x = blobs.first?.root.position.x ?? 0
        camera.look(at: [x, 0, targetZ], from: [x, 24, targetZ + 28], relativeTo: nil)
    }

    private func paint(_ entity: Entity, dark: Bool, foliage: [[any RealityKit.Material]]) {
        let parts = entity.name.split(separator: "-")
        if parts.count == 3, parts[0] == "leaves", let variant = Int(parts[1]), let band = Int(parts[2]),
            foliage.indices.contains(variant), foliage[variant].indices.contains(band),
            let model = entity as? ModelEntity
        {
            model.model?.materials = [foliage[variant][band]]
        }
        let color: UIColor?
        switch entity.name {
        case "grass": color = dark ? hex(0x172D2E) : hex(0xC8DDB2)
        case "path": color = dark ? hex(0x526162) : hex(0xF1DFB4)
        case "path-edge": color = dark ? hex(0x364D49) : hex(0xBCBD91)
        case "trunk": color = dark ? hex(0x62524B) : hex(0x8F6D52)
        default: color = nil
        }
        if let color, let model = entity as? ModelEntity {
            model.model?.materials = [SimpleMaterial(color: color, roughness: 1, isMetallic: false)]
        }
        for child in entity.children { paint(child, dark: dark, foliage: foliage) }
    }

    private func hex(_ value: UInt32) -> UIColor {
        UIColor(
            red: Double((value >> 16) & 255) / 255, green: Double((value >> 8) & 255) / 255,
            blue: Double(value & 255) / 255, alpha: 1)
    }
}
