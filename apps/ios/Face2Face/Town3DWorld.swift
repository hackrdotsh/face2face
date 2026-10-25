import Face2FaceCore
import RealityKit
import SwiftUI
import UIKit
import simd

@available(iOS 18.0, *)
@MainActor
final class Town3DWorld {
    let root = Entity()
    let camera = Entity()
    private let sun = DirectionalLight()
    private let fill = DirectionalLight()
    private var residents: [Forest3DAssets.Blob] = []
    private var residentSeeds: [String] = []
    private var waves: [Entity] = []
    private var isDark: Bool?
    private var viewport = CGSize.zero
    private(set) var publicVisitorCount = 0

    init() throws {
        root.name = "town-world"
        var lens = OrthographicCameraComponent()
        lens.scale = 5
        lens.scaleDirection = .horizontal
        lens.near = 0.1
        lens.far = 80
        camera.components.set(lens)
        camera.look(at: .zero, from: [0, 18, 14], relativeTo: nil)
        root.addChild(camera)
        sun.look(at: .zero, from: [-10, 18, 10], relativeTo: nil)
        sun.shadow = .init(shadowProjection: .automatic(maximumDistance: 55), depthBias: 0.1)
        fill.look(at: .zero, from: [10, 12, -10], relativeTo: nil)
        root.addChild(sun)
        root.addChild(fill)

        let coast: [CGPoint] = [
            CGPoint(x: -100, y: -150), CGPoint(x: 500, y: -150), CGPoint(x: 500, y: 576),
            CGPoint(x: 340, y: 583), CGPoint(x: 270, y: 594), CGPoint(x: 180, y: 580), CGPoint(x: 90, y: 592),
            CGPoint(x: -100, y: 577),
        ]
        root.addChild(Town3DAssets.model(try surface(coast), name: "grass"))
        let bank = Town3DAssets.model(try surface(coast), name: "bank", at: [0, -0.12, 0.09])
        bank.scale = [1.012, 1, 1.012]
        root.addChild(bank)
        root.addChild(
            Town3DAssets.model(.generatePlane(width: 80, depth: 100), name: "water", at: [0, -0.18, 0]))
        let paths: [CGRect] = [
            CGRect(x: 185, y: 67, width: 28, height: 488), CGRect(x: 43, y: 207, width: 155, height: 28),
            CGRect(x: 199, y: 249, width: 177, height: 28), CGRect(x: 348, y: 263, width: 28, height: 142),
            CGRect(x: 199, y: 391, width: 163, height: 28), CGRect(x: 43, y: 399, width: 156, height: 28),
            CGRect(x: 43, y: 413, width: 28, height: 128), CGRect(x: 57, y: 527, width: 142, height: 28),
        ]
        root.addChild(
            Town3DAssets.model(
                try pathSurface(paths.map { $0.insetBy(dx: -3, dy: -3) }), name: "stone", at: [0, 0.008, 0]))
        root.addChild(Town3DAssets.model(try pathSurface(paths), name: "path", at: [0, 0.018, 0]))

        for (entity, point) in [
            (try Town3DAssets.building(cafe: false), CGPoint(x: 112, y: 195)),
            (try Town3DAssets.building(cafe: true), CGPoint(x: 291, y: 329)),
            (try Town3DAssets.noticeBoard(), CGPoint(x: 124, y: 518)),
            (Town3DAssets.bench(), CGPoint(x: 294, y: 512)),
        ] {
            entity.position = Self.world(point)
            root.addChild(entity)
        }

        let treePoints = [
            CGPoint(x: 26, y: 55), CGPoint(x: 108, y: 53), CGPoint(x: 282, y: 53), CGPoint(x: 374, y: 55),
            CGPoint(x: 5, y: 166), CGPoint(x: 6, y: 320), CGPoint(x: 394, y: 164), CGPoint(x: 397, y: 492),
            CGPoint(x: 295, y: 479),
        ]
        for (index, point) in treePoints.enumerated() {
            let tree = try Forest3DAssets.pine(variant: index % 3)
            tree.position = Self.world(point)
            tree.scale = SIMD3(repeating: index < 4 || index == 8 ? 0.5 : 0.35)
            root.addChild(tree)
        }
        for index in 0..<15 {
            let x = CGFloat((index * 73 + 81) % 330 + 35)
            let y = CGFloat((index * 41 + 44) % 440 + 75)
            guard !paths.contains(where: { $0.insetBy(dx: -12, dy: -12).contains(CGPoint(x: x, y: y)) })
            else { continue }
            let point = Self.world(CGPoint(x: x, y: y))
            root.addChild(
                Town3DAssets.model(
                    .generateCylinder(height: 0.14, radius: 0.014), name: "stem", at: point + [0, 0.07, 0]))
            let flowers = Town3DAssets.model(
                .generateSphere(radius: 0.065), name: "flower",
                at: point + [0, 0.17, 0])
            root.addChild(flowers)
        }
        for x in stride(from: 14.0, through: 388, by: 23) {
            let post = Town3DAssets.box(
                [0.06, 0.43, 0.06], name: "wood", at: Self.world(CGPoint(x: x, y: 575)) + [0, 0.215, 0])
            root.addChild(post)
        }
        let railPoint = Self.world(CGPoint(x: 200, y: 575))
        for height: Float in [0.2, 0.4] {
            root.addChild(Town3DAssets.box([9.5, 0.05, 0.05], name: "wood", at: railPoint + [0, height, 0]))
        }
        for row in 0..<8 {
            let wave = Town3DAssets.model(
                try waveMesh(), name: "water-foam", at: [0, -0.15, 9.2 + Float(row) * 1.3])
            waves.append(wave)
            root.addChild(wave)
        }
        try updateVisitors([])
        configure(dark: false, viewport: CGSize(width: 400, height: 640))
        update(time: 0)
    }

    func configure(dark: Bool, viewport: CGSize) {
        let scale = min(viewport.width / 400, viewport.height / 640)
        if self.viewport != viewport, scale > 0,
            var lens = camera.components[OrthographicCameraComponent.self]
        {
            lens.scale = Float(viewport.width / (80 * scale))
            camera.components.set(lens)
            self.viewport = viewport
        }
        guard isDark != dark else { return }
        isDark = dark
        paint(root, dark: dark, foliage: Forest3DAssets.foliageMaterials(dark: dark))
        sun.light.intensity = dark ? 650 : 1_800
        sun.light.color = dark ? UIColor(red: 0.75, green: 0.8, blue: 1, alpha: 1) : .white
        fill.light.intensity = dark ? 180 : 550
    }

    func updateVisitors(_ visitors: [PublicTownFriend]) throws {
        let visible = Array(visitors.prefix(3))
        publicVisitorCount = visible.count
        let seeds = (0..<3).map { $0 < visible.count ? visible[$0].avatar.seed : "decorative-\($0)" }
        guard seeds != residentSeeds else { return }
        for resident in residents { resident.root.removeFromParent() }
        residents = []
        for index in 0..<3 {
            let fallback: [UInt8] = [
                UInt8(index), 1, UInt8(24 + index * 75), 29, 130, 216, 96, 190, 118, 230, 102, 32, 118, 190,
                128, 48,
            ]
            let blob =
                try index < visible.count
                ? (Forest3DAssets.blob(seed: visible[index].avatar.seed)
                    ?? Forest3DAssets.blob(seed: fallback)) : Forest3DAssets.blob(seed: fallback)
            blob.root.name = "town-blob-\(index)"
            blob.root.scale = SIMD3(repeating: 0.55)
            residents.append(blob)
            root.addChild(blob.root)
        }
        residentSeeds = seeds
    }

    func update(time: Double) {
        let time = time.isFinite ? max(0, time) : 0
        for (index, resident) in residents.enumerated() {
            let pose = TownResidentMotion.pose(slot: index, time: time)
            resident.root.position = Self.world(pose.point)
            resident.pose(at: pose.standing ? 0 : time + Double(index), walkingAway: !pose.facingForward)
        }
        for (index, wave) in waves.enumerated() {
            wave.position.x = Float(sin(time * 0.65 + Double(index))) * 0.18
            wave.position.z = 9.2 + Float(index) * 1.3 + Float(sin(time * 0.8 + Double(index))) * 0.09
        }
    }

    static func world(_ point: CGPoint) -> SIMD3<Float> {
        TownProjection.world(x: point.x, y: point.y)
    }

    private func paint(_ entity: Entity, dark: Bool, foliage: [[any RealityKit.Material]]) {
        let parts = entity.name.split(separator: "-")
        if parts.count == 3, parts[0] == "leaves", let variant = Int(parts[1]), let band = Int(parts[2]),
            foliage.indices.contains(variant), foliage[variant].indices.contains(band),
            let model = entity as? ModelEntity
        {
            model.model?.materials = [foliage[variant][band]]
        }
        let values: (UInt32, UInt32)? =
            switch entity.name {
            case "grass": (0xDCECDD, 0x101E28)
            case "path": (0xFCF1D9, 0x34424E)
            case "bank": (0xCFB992, 0x665E53)
            case "water": (0x7FBFD6, 0x1E3646)
            case "stone": (0xE9DEC8, 0x4B5665)
            case "stem": (0x6C985F, 0x325C4C)
            case "wall": (0xFFFDF8, 0x354354)
            case "roof-cafe": (0x85ADA2, 0x527D77)
            case "roof-venue": (0xC99ECD, 0x76619D)
            case "wood", "trunk": (0x9D897C, 0x756760)
            case "window": (0xFBE7C0, 0xF5D18E)
            case "flower": (0xF2B9CA, 0xBC85A8)
            case "gold": (0xD7AE63, 0xBC9665)
            case "cork": (0xD9B991, 0x806A56)
            default: nil
            }
        if let values, let model = entity as? ModelEntity {
            let color = Forest3DAssets.color(hex: dark ? values.1 : values.0)
            model.model?.materials =
                entity.name == "window"
                ? [UnlitMaterial(color: color)]
                : [
                    SimpleMaterial(
                        color: color, roughness: entity.name == "water" ? 0.25 : 1, isMetallic: false)
                ]
        } else if entity.name == "water-foam", let model = entity as? ModelEntity {
            var material = UnlitMaterial(color: Forest3DAssets.color(hex: dark ? 0xB2D8DF : 0xFFFDF8))
            material.blending = .transparent(opacity: 0.25)
            material.writesDepth = false
            model.model?.materials = [material]
        }
        for child in entity.children { paint(child, dark: dark, foliage: foliage) }
    }

    private func surface(_ points: [CGPoint]) throws -> MeshResource {
        var descriptor = MeshDescriptor(name: "town-ground")
        descriptor.positions = MeshBuffers.Positions(points.map(Self.world))
        descriptor.normals = MeshBuffers.Normals(Array(repeating: [0, 1, 0], count: points.count))
        descriptor.primitives = .triangles(
            (1..<(points.count - 1)).flatMap { [UInt32(0), UInt32($0 + 1), UInt32($0)] })
        return try MeshResource.generate(from: [descriptor])
    }

    private func pathSurface(_ rects: [CGRect]) throws -> MeshResource {
        let xs = Set(rects.flatMap { [$0.minX, $0.maxX] }).sorted()
        let ys = Set(rects.flatMap { [$0.minY, $0.maxY] }).sorted()
        var points: [SIMD3<Float>] = []
        var indices: [UInt32] = []
        for x in 0..<(xs.count - 1) {
            for y in 0..<(ys.count - 1) {
                let center = CGPoint(x: (xs[x] + xs[x + 1]) / 2, y: (ys[y] + ys[y + 1]) / 2)
                guard rects.contains(where: { $0.contains(center) }) else { continue }
                let start = UInt32(points.count)
                points += [
                    CGPoint(x: xs[x], y: ys[y]), CGPoint(x: xs[x + 1], y: ys[y]),
                    CGPoint(x: xs[x + 1], y: ys[y + 1]), CGPoint(x: xs[x], y: ys[y + 1]),
                ].map(Self.world)
                indices += [start, start + 2, start + 1, start, start + 3, start + 2]
            }
        }
        var descriptor = MeshDescriptor(name: "town-paths")
        descriptor.positions = MeshBuffers.Positions(points)
        descriptor.normals = MeshBuffers.Normals(Array(repeating: [0, 1, 0], count: points.count))
        descriptor.primitives = .triangles(indices)
        return try MeshResource.generate(from: [descriptor])
    }

    private func waveMesh() throws -> MeshResource {
        var points: [SIMD3<Float>] = []
        var indices: [UInt32] = []
        for index in 0...40 {
            let x = Float(index) * 0.3 - 6
            let z = sin(x * 2) * 0.05
            points += [[x, 0, z], [x, 0, z + 0.022]]
            if index < 40 {
                let i = UInt32(index * 2)
                indices += [i, i + 1, i + 2, i + 1, i + 3, i + 2]
            }
        }
        var descriptor = MeshDescriptor(name: "town-wave")
        descriptor.positions = MeshBuffers.Positions(points)
        descriptor.normals = MeshBuffers.Normals(Array(repeating: [0, 1, 0], count: points.count))
        descriptor.primitives = .triangles(indices)
        return try MeshResource.generate(from: [descriptor])
    }
}
