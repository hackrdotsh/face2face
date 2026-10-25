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

        root.addChild(
            Town3DAssets.model(.generatePlane(width: 80, depth: 100), name: "grass", at: [0, -0.04, 0]))
        let square = [
            CGPoint(x: 48, y: 135), CGPoint(x: 351, y: 135), CGPoint(x: 375, y: 160),
            CGPoint(x: 375, y: 521), CGPoint(x: 348, y: 548), CGPoint(x: 49, y: 548),
            CGPoint(x: 25, y: 522), CGPoint(x: 25, y: 160),
        ]
        root.addChild(Town3DAssets.model(try surface(square), name: "plaza", at: [0, 0.005, 0]))
        let paths: [CGRect] = [
            CGRect(x: 181, y: 548, width: 38, height: 180), CGRect(x: 185, y: 62, width: 30, height: 80),
        ]
        root.addChild(
            Town3DAssets.model(
                try pathSurface(paths.map { $0.insetBy(dx: -3, dy: -3) }), name: "stone", at: [0, 0.008, 0]))
        root.addChild(Town3DAssets.model(try pathSurface(paths), name: "path", at: [0, 0.018, 0]))

        for (entity, point) in [
            (try Town3DAssets.marketStall(cafe: false), TownPlazaLayout.position(for: .encounters)),
            (try Town3DAssets.marketStall(cafe: true), TownPlazaLayout.position(for: .connections)),
            (try Town3DAssets.noticeBoard(), TownPlazaLayout.position(for: .forums)),
            (Town3DAssets.bench(), CGPoint(x: 300, y: 532)),
        ] {
            entity.position = Self.world(point)
            root.addChild(entity)
        }
        let fountain = try Town3DAssets.fountain()
        fountain.position = Self.world(CGPoint(x: 208, y: 363))
        waves = fountain.children.filter { $0.name == "water-foam" }.map { $0 }
        root.addChild(fountain)

        for frame in [
            CGRect(x: 30, y: 290, width: 50, height: 105), CGRect(x: 322, y: 294, width: 48, height: 120),
            CGRect(x: 277, y: 444, width: 87, height: 72),
        ] {
            let garden = Town3DAssets.garden(
                width: Float(frame.width / 40), depth: Float(frame.height / (40 * TownProjection.sinePitch)))
            garden.position = Self.world(CGPoint(x: frame.midX, y: frame.midY))
            root.addChild(garden)
        }
        for point in [
            CGPoint(x: 50, y: 277), CGPoint(x: 350, y: 277), CGPoint(x: 162, y: 128), CGPoint(x: 238, y: 128),
        ] {
            let pot = Town3DAssets.flowerpot()
            pot.position = Self.world(point)
            root.addChild(pot)
        }
        for (index, point) in [
            CGPoint(x: 54, y: 323), CGPoint(x: 54, y: 380), CGPoint(x: 345, y: 329),
            CGPoint(x: 346, y: 402), CGPoint(x: 296, y: 478), CGPoint(x: 342, y: 488),
        ].enumerated() {
            let tree = try Forest3DAssets.pine(variant: index % 3)
            tree.position = Self.world(point) + [0, 0.16, 0]
            tree.scale = SIMD3(repeating: index > 3 ? 0.32 : 0.27)
            root.addChild(tree)
        }

        let treePoints = [
            CGPoint(x: -5, y: 94), CGPoint(x: 39, y: 110), CGPoint(x: 79, y: 87),
            CGPoint(x: 118, y: 112), CGPoint(x: 155, y: 89),
            CGPoint(x: 245, y: 93), CGPoint(x: 284, y: 113), CGPoint(x: 325, y: 86),
            CGPoint(x: 364, y: 112), CGPoint(x: 405, y: 91),
            CGPoint(x: 8, y: 170), CGPoint(x: -15, y: 222), CGPoint(x: 12, y: 272),
            CGPoint(x: -12, y: 325), CGPoint(x: 7, y: 378), CGPoint(x: -13, y: 431),
            CGPoint(x: 10, y: 484), CGPoint(x: -8, y: 540),
            CGPoint(x: 395, y: 173), CGPoint(x: 416, y: 224), CGPoint(x: 392, y: 276),
            CGPoint(x: 414, y: 329), CGPoint(x: 395, y: 381), CGPoint(x: 418, y: 434),
            CGPoint(x: 392, y: 488), CGPoint(x: 411, y: 540),
            CGPoint(x: 22, y: 589), CGPoint(x: 61, y: 619), CGPoint(x: 100, y: 590),
            CGPoint(x: 142, y: 616), CGPoint(x: 258, y: 614), CGPoint(x: 298, y: 588),
            CGPoint(x: 341, y: 619), CGPoint(x: 381, y: 587),
        ]
        for (index, point) in treePoints.enumerated() {
            let tree = try Forest3DAssets.pine(variant: index % 3)
            tree.position = Self.world(point)
            tree.scale = SIMD3(repeating: [Float(0.42), 0.5, 0.38, 0.46][index % 4])
            root.addChild(tree)
        }
        for index in 0..<15 {
            let x = CGFloat((index * 73 + 81) % 330 + 35)
            let y = CGFloat((index * 41 + 44) % 440 + 75)
            guard !CGRect(x: 25, y: 135, width: 350, height: 413).contains(CGPoint(x: x, y: y)) else {
                continue
            }
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
            let pose = TownPlazaLayout.resident(slot: index, time: time)
            resident.root.position = Self.world(pose.point)
            resident.pose(at: pose.standing ? 0 : time + Double(index), walkingAway: !pose.facingForward)
        }
        for (index, wave) in waves.enumerated() {
            let phase = (Float(time * 0.3) + Float(index) / 3).truncatingRemainder(dividingBy: 1)
            wave.scale = SIMD3(repeating: 0.15 + phase * 0.62)
            wave.components.set(OpacityComponent(opacity: 1 - phase))
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
            case "plaza": (0xEFE3CD, 0x3B4651)
            case "garden-edge": (0xB4AD91, 0x53604E)
            case "garden-grass": (0xA6C58A, 0x254838)
            case "shrub": (0x5B955A, 0x35664F)
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
