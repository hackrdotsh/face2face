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
        let flat = ["grass", "bank", "water", "path", "stone", "water-foam"].contains(name)
        entity.components.set(DynamicLightShadowComponent(castsShadow: !flat))
        return entity
    }

    static func box(_ size: SIMD3<Float>, name: String, at position: SIMD3<Float>) -> ModelEntity {
        model(
            .generateBox(size: size, cornerRadius: min(0.04, min(size.x, min(size.y, size.z)) / 4)),
            name: name, at: position)
    }

    static func building(cafe: Bool) throws -> Entity {
        let root = Entity()
        root.name = cafe ? "town-cafe" : "town-venue"
        root.addChild(box([3.1, 0.22, 2.35], name: "stone", at: [0, 0.11, 0]))
        root.addChild(box([2.65, 1.6, 2.0], name: "wall", at: [0, 1.02, 0]))
        let roof = model(
            try pitchedRoof(width: 3.1, depth: 2.45, height: 0.95), name: cafe ? "roof-cafe" : "roof-venue",
            at: [0, 1.81, 0])
        root.addChild(roof)
        root.addChild(box([0.24, 0.7, 0.28], name: "stone", at: [0.8, 2.55, -0.45]))
        root.addChild(box([0.33, 0.08, 0.37], name: "wood", at: [0.8, 2.94, -0.45]))
        for x: Float in [-0.87, 0.87] {
            root.addChild(box([0.66, 0.83, 0.09], name: "wood", at: [x, 0.98, 1.03]))
            root.addChild(box([0.55, 0.7, 0.06], name: "window", at: [x, 0.98, 1.09]))
            root.addChild(box([0.035, 0.7, 0.04], name: "wood", at: [x, 0.98, 1.14]))
            root.addChild(box([0.55, 0.035, 0.04], name: "wood", at: [x, 0.98, 1.14]))
            root.addChild(box([0.7, 0.14, 0.24], name: "wood", at: [x, 0.52, 1.14]))
            for petal in 0..<3 {
                root.addChild(
                    model(
                        .generateSphere(radius: 0.075), name: "flower",
                        at: [x - 0.21 + Float(petal) * 0.21, 0.63, 1.17]))
            }
        }
        root.addChild(box([0.59, 1.12, 0.09], name: "wood", at: [0, 0.79, 1.04]))
        root.addChild(box([0.43, 0.61, 0.04], name: "window", at: [0, 0.99, 1.1]))
        root.addChild(model(.generateSphere(radius: 0.045), name: "gold", at: [0.17, 0.65, 1.12]))
        root.addChild(box([0.84, 0.12, 0.42], name: "stone", at: [0, 0.18, 1.18]))

        if cafe {
            for stripe in 0..<8 {
                let awning = box(
                    [0.39, 0.12, 0.57], name: stripe.isMultiple(of: 2) ? "roof-cafe" : "wall",
                    at: [-1.36 + Float(stripe) * 0.39, 1.65, 1.25])
                awning.orientation = simd_quatf(angle: 0.18, axis: [1, 0, 0])
                root.addChild(awning)
            }
            root.addChild(box([0.08, 0.8, 0.08], name: "wood", at: [-1.12, 2.45, 1.2]))
            root.addChild(box([0.55, 0.08, 0.08], name: "wood", at: [-0.89, 2.83, 1.2]))
            root.addChild(
                try sign("cup.and.saucer.fill", width: 0.62, height: 0.55, at: [-0.65, 2.52, 1.24]))
            for x: Float in [-0.83, 0.83] { root.addChild(table(at: [x, 0, 1.94])) }
        } else {
            root.addChild(box([2.95, 0.34, 0.17], name: "roof-venue", at: [0, 1.7, 1.11]))
            for index in 0..<9 {
                root.addChild(
                    model(
                        .generateSphere(radius: 0.045), name: "window",
                        at: [-1.28 + Float(index) * 0.32, 1.61, 1.22]))
            }
            root.addChild(try sign("sparkles", width: 0.44, height: 0.3, at: [0, 1.74, 1.21]))
        }
        let shadow = try Forest3DAssets.contactShadow(width: 3.8, depth: 3.3)
        shadow.position = [0.12, 0.025, 0.15]
        root.addChild(shadow)
        return root
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
