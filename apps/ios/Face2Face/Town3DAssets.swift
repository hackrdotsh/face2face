import Face2FaceCore
import RealityKit
import UIKit
import simd

@available(iOS 18.0, *)
@MainActor
enum Town3DAssets {
    static func model(_ mesh: MeshResource, name: String, at position: SIMD3<Float> = .zero) -> ModelEntity {
        let entity = ModelEntity(mesh: mesh, materials: [SimpleMaterial()])
        entity.name = name
        entity.position = position
        let flat = ["grass", "bank", "water", "path", "stone", "water-foam", "plaza"].contains(name)
        entity.components.set(DynamicLightShadowComponent(castsShadow: !flat))
        return entity
    }

    static func box(_ size: SIMD3<Float>, name: String, at position: SIMD3<Float>) -> ModelEntity {
        model(
            .generateBox(size: size, cornerRadius: min(0.04, min(size.x, min(size.y, size.z)) / 4)),
            name: name, at: position)
    }

    static func noticeBoard() throws -> Entity {
        let root = Entity()
        root.name = "town-board"
        for x: Float in [-0.83, 0.83] {
            root.addChild(box([0.14, 1.72, 0.16], name: "wood", at: [x, 0.86, 0]))
        }
        root.addChild(box([2.25, 1.3, 0.2], name: "wood", at: [0, 1.36, 0]))
        root.addChild(box([2.06, 1.12, 0.06], name: "cork", at: [0, 1.36, 0.14]))
        root.addChild(
            model(
                try pitchedRoof(width: 2.5, depth: 0.65, height: 0.28), name: "roof-cafe", at: [0, 2.01, 0]))
        for (index, name) in ["music.note", "heart.fill", "leaf.fill"].enumerated() {
            let note = try sign(
                name, width: 0.53, height: 0.74, at: [-0.68 + Float(index) * 0.68, 1.35, 0.18])
            note.orientation = simd_quatf(angle: index == 1 ? 0.06 : -0.06, axis: [0, 0, 1])
            root.addChild(note)
            root.addChild(
                model(
                    .generateSphere(radius: 0.035), name: "gold",
                    at: [-0.68 + Float(index) * 0.68, 1.71, 0.24]))
        }
        return root
    }

    static func marketStall(cafe: Bool) throws -> Entity {
        let root = Entity()
        root.name = cafe ? "town-cafe" : "town-venue"
        root.addChild(box([2.65, 0.08, 2.05], name: "stone", at: [0, 0.04, 0.05]))
        let shadow = try Forest3DAssets.contactShadow(width: 3.1, depth: 2.5)
        shadow.position.y = 0.006
        root.addChild(shadow)

        let canvas = Entity()
        canvas.name = "stall-canopy"
        let stripeWidth: Float = 2.7 / 12
        let stripeMesh = try Town3DGeometry.canopyStripe(width: stripeWidth)
        let scallopMesh = try Town3DGeometry.scallop(width: stripeWidth)
        for stripe in 0..<12 {
            let name = stripe.isMultiple(of: 2) ? (cafe ? "canvas-mint" : "canvas-lilac") : "canvas-cream"
            let x = -1.35 + stripeWidth * (Float(stripe) + 0.5)
            canvas.addChild(model(stripeMesh, name: name, at: [x, 0, 0]))
            canvas.addChild(model(scallopMesh, name: name, at: [x, 1.7, 0.525]))
        }
        root.addChild(canvas)

        for x: Float in [-1.16, 1.16] {
            root.addChild(beam(from: [x, 0.08, -0.79], to: [x, 2.07, -0.79]))
            root.addChild(beam(from: [x, 0.08, 0.37], to: [x, 1.71, 0.37]))
            root.addChild(beam(from: [x, 2.03, -0.79], to: [x, 1.68, 0.37]))
            root.addChild(beam(from: [x, 1.3, 0.37], to: [x * 0.75, 1.68, 0.37]))
            for z: Float in [-0.79, 0.37] {
                root.addChild(box([0.11, 0.12, 0.11], name: "iron", at: [x, 0.14, z]))
            }
        }
        root.addChild(beam(from: [-1.18, 1.66, 0.37], to: [1.18, 1.66, 0.37]))
        root.addChild(beam(from: [-1.18, 2.02, -0.79], to: [1.18, 2.02, -0.79]))

        let counter = Entity()
        counter.name = "stall-counter"
        counter.addChild(box([2.2, 0.64, 0.58], name: "wood", at: [0, 0.41, 0.73]))
        for plank in 0..<11 {
            counter.addChild(
                box(
                    [0.19, 0.57, 0.055], name: plank.isMultiple(of: 2) ? "timber" : "timber-light",
                    at: [-1 + Float(plank) * 0.2, 0.42, 1.04]))
        }
        counter.addChild(box([2.3, 0.085, 0.76], name: "timber-light", at: [0, 0.79, 0.73]))
        counter.addChild(box([2.24, 0.065, 0.06], name: "timber", at: [0, 0.16, 1.075]))
        root.addChild(counter)

        for x: Float in [-0.24, 0.24] {
            root.addChild(beam(from: [x, 1.67, 0.57], to: [x, 1.4, 0.57], width: 0.025, name: "iron"))
        }
        root.addChild(box([0.65, 0.39, 0.065], name: "timber", at: [0, 1.36, 0.57]))
        root.addChild(
            try sign(
                cafe ? "cup.and.saucer.fill" : "sparkles", width: 0.32, height: 0.32, at: [0, 1.36, 0.61]))

        if cafe {
            root.addChild(box([0.65, 0.36, 0.37], name: "canvas-mint", at: [0.51, 1.01, 0.53]))
            root.addChild(box([0.57, 0.045, 0.42], name: "iron", at: [0.51, 0.855, 0.58]))
            root.addChild(box([0.56, 0.08, 0.07], name: "iron", at: [0.51, 1.12, 0.745]))
            for x: Float in [0.36, 0.66] {
                root.addChild(
                    model(
                        .generateCylinder(height: 0.055, radius: 0.023), name: "gold", at: [x, 1.02, 0.745]))
            }
            for x: Float in [-0.72, -0.38] { root.addChild(try cup(at: [x, 0.84, 0.8])) }
            root.addChild(table(at: [0.72, 0, 1.62]))
            let menu = box([0.39, 0.59, 0.075], name: "timber", at: [-0.77, 0.39, 1.55])
            menu.orientation = simd_quatf(angle: -0.14, axis: [1, 0, 0])
            root.addChild(menu)
            root.addChild(box([0.3, 0.45, 0.025], name: "iron", at: [-0.77, 0.41, 1.63]))
            for row in 0..<3 {
                root.addChild(
                    box(
                        [0.2 - Float(row) * 0.025, 0.015, 0.008], name: "canvas-cream",
                        at: [-0.77, 0.51 - Float(row) * 0.09, 1.65]))
            }
        } else {
            for (index, x) in [Float(-0.72), 0, 0.72].enumerated() {
                let crate = produceCrate(kind: index)
                crate.position = [x, 0.84, 0.76]
                root.addChild(crate)
            }
        }
        for x: Float in [-1.02, 1.02] {
            root.addChild(model(.generateSphere(radius: 0.065), name: "window", at: [x, 1.5, 0.48]))
        }
        return root
    }

    static func fountain() throws -> Entity {
        let root = Entity()
        root.name = "town-fountain"
        let basin: [SIMD2<Float>] = [
            [1.03, 0.035], [1.1, 0.1], [1.1, 0.24], [1.04, 0.32],
            [0.88, 0.32], [0.82, 0.25], [0.82, 0.1], [1.03, 0.035],
        ]
        root.addChild(model(try Town3DGeometry.lathe(basin), name: "stone-cut"))
        root.addChild(model(.generateCylinder(height: 0.06, radius: 0.84), name: "stone", at: [0, 0.09, 0]))
        root.addChild(
            model(.generateCylinder(height: 0.015, radius: 0.845), name: "water", at: [0, 0.205, 0]))
        let column: [SIMD2<Float>] = [
            [0.23, 0.1], [0.23, 0.21], [0.15, 0.26], [0.11, 0.48],
            [0.18, 0.54], [0.22, 0.6], [0.18, 0.66], [0.09, 0.69],
        ]
        root.addChild(model(try Town3DGeometry.lathe(column), name: "stone-cut"))
        root.addChild(model(.generateSphere(radius: 0.085), name: "gold", at: [0, 0.73, 0]))
        for stream in 0..<4 {
            root.addChild(
                model(
                    try Town3DGeometry.waterArc(angle: Float(stream) * .pi / 2 + .pi / 4),
                    name: "water-stream"))
        }
        for index in 0..<3 {
            let ripple = model(try ring(), name: "water-foam", at: [0, 0.217, 0])
            ripple.scale = SIMD3(repeating: 0.3 + Float(index) * 0.25)
            root.addChild(ripple)
        }
        return root
    }

    private static func beam(
        from start: SIMD3<Float>, to end: SIMD3<Float>, width: Float = 0.085, name: String = "timber"
    ) -> ModelEntity {
        let direction = end - start
        let beam = box([width, simd_length(direction), width], name: name, at: (start + end) / 2)
        beam.orientation = simd_quatf(from: [0, 1, 0], to: simd_normalize(direction))
        return beam
    }

    private static func produceCrate(kind: Int) -> Entity {
        let root = Entity()
        root.addChild(box([0.6, 0.045, 0.47], name: "timber", at: [0, 0.023, 0]))
        for y: Float in [0.07, 0.16] {
            for z: Float in [-0.22, 0.22] {
                root.addChild(box([0.6, 0.065, 0.035], name: "timber-light", at: [0, y, z]))
            }
            for x: Float in [-0.28, 0.28] {
                root.addChild(box([0.035, 0.065, 0.42], name: "timber-light", at: [x, y, 0]))
            }
        }
        for row in 0..<2 {
            for column in 0..<3 {
                let fruit = model(
                    .generateSphere(radius: 0.082), name: ["apple", "orange", "shrub"][kind],
                    at: [-0.17 + Float(column) * 0.17, 0.14, -0.095 + Float(row) * 0.19])
                fruit.scale.y = kind == 2 ? 1.15 : 0.92
                root.addChild(fruit)
            }
        }
        return root
    }

    private static func cup(at position: SIMD3<Float>) throws -> Entity {
        let root = Entity()
        root.position = position
        root.addChild(model(.generateCylinder(height: 0.02, radius: 0.13), name: "canvas-cream"))
        let profile: [SIMD2<Float>] = [[0.055, 0.02], [0.085, 0.17], [0.068, 0.17], [0.05, 0.035]]
        root.addChild(model(try Town3DGeometry.lathe(profile, segments: 24), name: "canvas-cream"))
        root.addChild(
            model(.generateCylinder(height: 0.008, radius: 0.067), name: "coffee", at: [0, 0.151, 0]))
        return root
    }

    static func garden(width: Float, depth: Float) -> Entity {
        let root = Entity()
        root.name = "plaza-garden"
        root.addChild(box([width, 0.12, depth], name: "garden-edge", at: [0, 0.06, 0]))
        root.addChild(box([width - 0.12, 0.04, depth - 0.12], name: "garden-grass", at: [0, 0.14, 0]))
        for index in 0..<4 {
            let z = -depth / 2 + 0.35 + Float(index) * (depth - 0.7) / 3
            let shrub = model(
                .generateSphere(radius: 0.2), name: "shrub",
                at: [index.isMultiple(of: 2) ? -width * 0.2 : width * 0.2, 0.29, z])
            shrub.scale = [1.2, 0.8, 1]
            root.addChild(shrub)
            root.addChild(
                model(.generateSphere(radius: 0.045), name: "flower", at: shrub.position + [0.06, 0.14, 0]))
        }
        return root
    }

    static func flowerpot() -> Entity {
        let root = Entity()
        root.addChild(model(.generateCylinder(height: 0.24, radius: 0.17), name: "cork", at: [0, 0.12, 0]))
        root.addChild(model(.generateSphere(radius: 0.21), name: "shrub", at: [0, 0.31, 0]))
        for x: Float in [-0.09, 0, 0.09] {
            root.addChild(model(.generateSphere(radius: 0.05), name: "flower", at: [x, 0.49, 0]))
        }
        return root
    }

    private static func ring() throws -> MeshResource {
        var points: [SIMD3<Float>] = []
        var indices: [UInt32] = []
        for index in 0..<48 {
            let angle = Float(index) / 48 * 2 * .pi
            for radius: Float in [0.96, 1] { points.append([cos(angle) * radius, 0, sin(angle) * radius]) }
            let i = UInt32(index * 2)
            let next = UInt32((index + 1) % 48 * 2)
            indices += [i, next, i + 1, i + 1, next, next + 1]
        }
        var descriptor = MeshDescriptor(name: "fountain-ripple")
        descriptor.positions = MeshBuffers.Positions(points)
        descriptor.normals = MeshBuffers.Normals(Array(repeating: [0, 1, 0], count: points.count))
        descriptor.primitives = .triangles(indices)
        return try MeshResource.generate(from: [descriptor])
    }

    static func bench() -> Entity {
        let root = Entity()
        for z: Float in [-0.14, 0, 0.14] {
            root.addChild(box([1.5, 0.07, 0.1], name: "wood", at: [0, 0.48, z]))
        }
        for y: Float in [0.73, 0.9] {
            root.addChild(box([1.5, 0.12, 0.08], name: "wood", at: [0, y, -0.2]))
        }
        for x: Float in [-0.55, 0.55] {
            root.addChild(box([0.08, 0.48, 0.42], name: "stone", at: [x, 0.24, 0]))
        }
        return root
    }

    private static func table(at position: SIMD3<Float>) -> Entity {
        let root = Entity()
        root.position = position
        root.addChild(model(.generateCylinder(height: 0.07, radius: 0.36), name: "wall", at: [0, 0.67, 0]))
        root.addChild(model(.generateCylinder(height: 0.65, radius: 0.065), name: "wood", at: [0, 0.325, 0]))
        for x: Float in [-0.53, 0.53] {
            root.addChild(box([0.3, 0.08, 0.3], name: "wood", at: [x, 0.37, 0]))
            root.addChild(box([0.3, 0.34, 0.06], name: "wood", at: [x, 0.55, -0.15]))
            for offset: Float in [-0.11, 0.11] {
                for z: Float in [-0.11, 0.11] {
                    root.addChild(box([0.035, 0.33, 0.035], name: "timber", at: [x + offset, 0.165, z]))
                }
            }
        }
        root.addChild(
            model(.generateCylinder(height: 0.12, radius: 0.065), name: "roof-cafe", at: [0, 0.76, 0]))
        return root
    }

    private static func sign(_ symbol: String, width: Float, height: Float, at position: SIMD3<Float>) throws
        -> Entity
    {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 96, height: 96)).image { context in
            UIColor(red: 1, green: 0.99, blue: 0.96, alpha: 1).setFill()
            context.fill(CGRect(x: 0, y: 0, width: 96, height: 96))
            UIImage(
                systemName: symbol,
                withConfiguration: UIImage.SymbolConfiguration(pointSize: 46, weight: .medium))?
                .withTintColor(
                    UIColor(red: 0.34, green: 0.4, blue: 0.34, alpha: 1), renderingMode: .alwaysOriginal
                )
                .draw(in: CGRect(x: 24, y: 24, width: 48, height: 48))
        }
        let texture = try TextureResource.generate(from: image.cgImage!, options: .init(semantic: .color))
        var material = UnlitMaterial(color: .white)
        material.color.texture = .init(texture)
        let sign = ModelEntity(mesh: .generatePlane(width: width, height: height), materials: [material])
        sign.name = "sign-art"
        sign.position = position
        return sign
    }

    static func pitchedRoof(width: Float, depth: Float, height: Float) throws -> MeshResource {
        let x = width / 2
        let z = depth / 2
        let points: [SIMD3<Float>] = [
            [-x, 0, -z], [x, 0, -z], [-x, 0, z], [x, 0, z], [0, height, -z], [0, height, z],
        ]
        let faces: [[UInt32]] = [[0, 2, 5], [0, 5, 4], [1, 4, 5], [1, 5, 3], [0, 4, 1], [2, 3, 5]]
        var vertices: [SIMD3<Float>] = []
        var normals: [SIMD3<Float>] = []
        var indices: [UInt32] = []
        for face in faces {
            let triangle = face.map { points[Int($0)] }
            let normal = simd_normalize(simd_cross(triangle[1] - triangle[0], triangle[2] - triangle[0]))
            let start = UInt32(vertices.count)
            vertices += triangle
            normals += Array(repeating: normal, count: 3)
            indices += [start, start + 1, start + 2]
        }
        var descriptor = MeshDescriptor(name: "pitched-roof")
        descriptor.positions = MeshBuffers.Positions(vertices)
        descriptor.normals = MeshBuffers.Normals(normals)
        descriptor.primitives = .triangles(indices)
        return try MeshResource.generate(from: [descriptor])
    }
}
