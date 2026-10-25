import Face2FaceCore
import RealityKit
import UIKit

@available(iOS 18.0, *)
@MainActor
enum Forest3DAssets {
    struct Blob {
        let root: Entity
        let body: Entity
        let shadow: Entity
        let eyes: [Entity]
        let eyePositions: [SIMD3<Float>]
        let motion: BlobIdleMotion

        func pose(at time: Double) {
            let pose = motion.pose(at: time)
            let breath = Float(sin(pose.breath))
            body.scale = [1 + breath * 0.025, 1 - breath * 0.035, 1 + breath * 0.025]
            body.position.y = 0.83 + abs(Float(sin(time * 3))) * 0.045
            root.orientation = simd_quatf(angle: Float(sin(time * 3)) * 0.045, axis: [0, 0, 1])
            shadow.orientation = root.orientation.inverse
            for (eye, position) in zip(eyes, eyePositions) {
                eye.position = position + [Float(pose.gaze) * 2, 0, 0]
                eye.scale.y = Float(pose.eyeOpenness)
            }
        }
    }

    static func blob(seed: [UInt8]) throws -> Blob {
        let avatar = BlobAvatar(seed: seed)
        let volume = BlobVolume(avatar: avatar)
        var descriptor = MeshDescriptor(name: "seeded-blob")
        descriptor.positions = MeshBuffers.Positions(volume.positions.map { [$0.x, $0.y, $0.z] })
        descriptor.normals = MeshBuffers.Normals(volume.normals.map { [$0.x, $0.y, $0.z] })
        descriptor.textureCoordinates = MeshBuffers.TextureCoordinates(
            volume.textureCoordinates.map { [$0.u, $0.v] })
        descriptor.primitives = .triangles(volume.indices)
        let mesh = try MeshResource.generate(from: [descriptor])
        let texture = try TextureResource.generate(
            from: gradient(avatar.fill), options: .init(semantic: .color))
        var material = SimpleMaterial(color: .white, roughness: 0.85, isMetallic: false)
        material.color.texture = .init(texture)
        let body = ModelEntity(mesh: mesh, materials: [material])
        body.components.set(DynamicLightShadowComponent(castsShadow: true))
        body.name = "blob-body"
        body.position.y = 0.83
        let root = Entity()
        root.name = "forest-blob"
        root.addChild(body)
        let shadow = try contactShadow(width: 2, depth: 1.5)
        shadow.position.y = 0.035
        root.addChild(shadow)
        var eyes: [Entity] = []
        var positions: [SIMD3<Float>] = []
        for eye in avatar.eyes {
            let x = Float(2 * (eye.x + eye.width / 2 - 0.5))
            let y = Float(2 * (0.5 - eye.y - eye.height / 2))
            let z = BlobVolume.depth * sqrt(max(0.05, 1 - x * x - y * y)) + 0.015
            let shape = ModelEntity(
                mesh: .generateBox(
                    size: [Float(eye.width * 2), Float(eye.height * 2), 0.065], cornerRadius: 0.032),
                materials: [UnlitMaterial(color: color(avatar.eyeColor))])
            shape.name = "blob-eye"
            shape.position = [x, y, z]
            body.addChild(shape)
            eyes.append(shape)
            positions.append(shape.position)
        }
        return Blob(
            root: root, body: body, shadow: shadow, eyes: eyes, eyePositions: positions,
            motion: BlobIdleMotion(seed: seed))
    }

    static func pine(variant: Int) throws -> Entity {
        let tree = Entity()
        tree.name = "forest-pine"
        let trunk = ModelEntity(
            mesh: .generateCylinder(height: 0.9, radius: 0.14), materials: [SimpleMaterial()])
        trunk.name = "trunk"
        trunk.position.y = 0.45
        tree.addChild(trunk)
        let shadow = try contactShadow(width: 2.6, depth: 2.3)
        shadow.position.y = 0.01
        tree.addChild(shadow)
        let tiers: [(Float, Float, Float)] = [
            (1.05, 1.45, 1.05), (0.87, 1.3, 1.75), (0.64, 1.1, 2.4), (0.36, 0.86, 2.98),
        ]
        for tier in tiers {
            let crown = ModelEntity(
                mesh: .generateCone(height: tier.1, radius: tier.0), materials: [SimpleMaterial()])
            crown.name = "leaves-\(variant)"
            crown.components.set(DynamicLightShadowComponent(castsShadow: true))
            crown.position.y = tier.2
            tree.addChild(crown)
        }
        return tree
    }

    static func path(width: Float) throws -> MeshResource {
        var positions: [SIMD3<Float>] = []
        var indices: [UInt32] = []
        for step in 0...128 {
            let z = Float(step) - 64
            let x = pathCenter(z)
            positions += [[x - width / 2, 0, z], [x + width / 2, 0, z]]
            if step < 128 {
                let i = UInt32(step * 2)
                indices += [i, i + 2, i + 1, i + 1, i + 2, i + 3]
            }
        }
        var descriptor = MeshDescriptor(name: "forest-path")
        descriptor.positions = MeshBuffers.Positions(positions)
        descriptor.normals = MeshBuffers.Normals(Array(repeating: [0, 1, 0], count: positions.count))
        descriptor.primitives = .triangles(indices)
        return try MeshResource.generate(from: [descriptor])
    }

    static func pathCenter(_ z: Float) -> Float { sin(z * .pi / 16) * 1.35 }

    private static func contactShadow(width: Float, depth: Float) throws -> ModelEntity {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 64, height: 64)).image { context in
            let colors = [UIColor.white.cgColor, UIColor.white.withAlphaComponent(0).cgColor]
            if let gradient = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors as CFArray, locations: [0, 1])
            {
                context.cgContext.drawRadialGradient(
                    gradient, startCenter: CGPoint(x: 32, y: 32), startRadius: 0,
                    endCenter: CGPoint(x: 32, y: 32), endRadius: 31, options: [])
            }
        }
        let texture = try TextureResource.generate(from: image.cgImage!, options: .init(semantic: .color))
        var material = UnlitMaterial(color: UIColor(red: 0.1, green: 0.14, blue: 0.1, alpha: 1))
        material.color.texture = .init(texture)
        material.blending = .transparent(opacity: 0.28)
        material.writesDepth = false
        let shadow = ModelEntity(mesh: .generatePlane(width: width, depth: depth), materials: [material])
        shadow.name = "contact-shadow"
        return shadow
    }

    private static func color(_ hsl: BlobAvatar.HSL) -> UIColor {
        let rgb = hsl.rgb
        return UIColor(red: rgb.red, green: rgb.green, blue: rgb.blue, alpha: 1)
    }

    private static func gradient(_ colors: [BlobAvatar.HSL]) -> CGImage {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 128, height: 128)).image { context in
            let rgb = colors.map { value -> CGColor in
                let rgb = value.rgb
                return UIColor(red: rgb.red, green: rgb.green, blue: rgb.blue, alpha: 1).cgColor
            }
            if let gradient = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: rgb as CFArray, locations: [0, 1])
            {
                context.cgContext.drawLinearGradient(
                    gradient, start: .zero, end: CGPoint(x: 128, y: 128), options: [])
            }
        }
        return image.cgImage!
    }
}
