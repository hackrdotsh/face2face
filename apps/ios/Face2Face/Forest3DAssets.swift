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
        let greeting: Entity
        let halo: Entity
        let eyes: [Entity]
        let eyePositions: [SIMD3<Float>]
        let motion: BlobIdleMotion

        func pose(
            at time: Double, greetingProgress: Double? = nil, facing: Float = 1, walkingAway: Bool = false
        ) {
            let pose = motion.pose(at: time)
            let breath = Float(sin(pose.breath))
            let hello = greetingProgress.map { Float(sin($0 * .pi)) } ?? 0
            body.scale = [
                1 + breath * 0.025 - hello * 0.04, 1 - breath * 0.035 + hello * 0.07, 1 + breath * 0.025,
            ]
            body.position.y = 0.83 + abs(Float(sin(time * 3))) * 0.045 + hello * 0.18
            let wiggle = Float(sin(time * 3)) * 0.045 + Float(sin(time * 13)) * hello * 0.1
            let heading: Float = walkingAway ? .pi - hello * 2 * .pi / 3 : -hello * .pi / 3
            root.orientation =
                simd_quatf(angle: heading, axis: [0, 1, 0])
                * simd_quatf(angle: wiggle, axis: [0, 0, 1])
            shadow.orientation = root.orientation.inverse
            halo.orientation = root.orientation.inverse
            halo.scale = SIMD3(repeating: 1 + Float(greetingProgress ?? 0) * 0.35)
            greeting.position = [-facing * 0.42, 2.05 + hello * 0.12, 0]
            greeting.isEnabled = hello > 0.001
            halo.isEnabled = hello > 0.001
            greeting.components.set(OpacityComponent(opacity: hello))
            halo.components.set(OpacityComponent(opacity: hello * 0.7))
            for (eye, position) in zip(eyes, eyePositions) {
                eye.position = position + [Float(pose.gaze) * 2, 0, 0]
                eye.scale.y = Float(pose.eyeOpenness)
            }
        }
    }

    static func blob(seed: [UInt8]) throws -> Blob {
        try blob(avatar: BlobAvatar(seed: seed), motion: BlobIdleMotion(seed: seed))
    }

    static func blob(seed: String) throws -> Blob? {
        guard let avatar = BlobAvatar(seed: seed), let motion = BlobIdleMotion(seed: seed) else { return nil }
        return try blob(avatar: avatar, motion: motion)
    }

    private static func blob(avatar: BlobAvatar, motion: BlobIdleMotion) throws -> Blob {
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
        let greeting = try greetingBubble()
        let halo = try greetingHalo()
        root.addChild(greeting)
        root.addChild(halo)
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
            root: root, body: body, shadow: shadow, greeting: greeting, halo: halo, eyes: eyes,
            eyePositions: positions,
            motion: motion)
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
        for (band, tier) in tiers.enumerated() {
            let crown = ModelEntity(
                mesh: .generateCone(height: tier.1, radius: tier.0), materials: [SimpleMaterial()])
            crown.name = "leaves-\(variant)-\(band)"
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

    private static func greetingBubble() throws -> Entity {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 96, height: 96)).image { context in
            let circle = CGRect(x: 4, y: 4, width: 88, height: 88)
            context.cgContext.setFillColor(UIColor(red: 1, green: 0.99, blue: 0.96, alpha: 1).cgColor)
            context.cgContext.fillEllipse(in: circle)
            context.cgContext.setStrokeColor(UIColor(red: 0.64, green: 0.52, blue: 0.77, alpha: 1).cgColor)
            context.cgContext.setLineWidth(5)
            context.cgContext.strokeEllipse(in: circle)
            let symbol = UIImage(
                systemName: "hand.wave.fill",
                withConfiguration: UIImage.SymbolConfiguration(pointSize: 48, weight: .medium))?
                .withTintColor(
                    UIColor(red: 0.2, green: 0.22, blue: 0.3, alpha: 1), renderingMode: .alwaysOriginal)
            symbol?.draw(in: CGRect(x: 25, y: 24, width: 46, height: 48))
        }
        let texture = try TextureResource.generate(from: image.cgImage!, options: .init(semantic: .color))
        var material = UnlitMaterial(color: .white)
        material.color.texture = .init(texture)
        material.blending = .transparent(opacity: 1.0)
        material.writesDepth = false
        let bubble = ModelEntity(mesh: .generatePlane(width: 0.65, height: 0.65), materials: [material])
        bubble.name = "greeting-bubble"
        bubble.isEnabled = false
        return bubble
    }

    private static func greetingHalo() throws -> Entity {
        var positions: [SIMD3<Float>] = []
        var indices: [UInt32] = []
        for index in 0..<48 {
            let angle = Float(index) / 48 * 2 * .pi
            for radius: Float in [0.98, 1.015] {
                positions.append([cos(angle) * radius, 0, sin(angle) * radius])
            }
            let a = UInt32(index * 2)
            let b = UInt32(((index + 1) % 48) * 2)
            indices += [a, b, a + 1, a + 1, b, b + 1]
        }
        var descriptor = MeshDescriptor(name: "greeting-ring")
        descriptor.positions = MeshBuffers.Positions(positions)
        descriptor.normals = MeshBuffers.Normals(Array(repeating: [0, 1, 0], count: positions.count))
        descriptor.primitives = .triangles(indices)
        let ring = ModelEntity(
            mesh: try MeshResource.generate(from: [descriptor]),
            materials: [UnlitMaterial(color: UIColor(red: 0.68, green: 0.55, blue: 0.8, alpha: 1))])
        ring.name = "greeting-halo"
        ring.position.y = 0.05
        ring.isEnabled = false
        return ring
    }

    static func contactShadow(width: Float, depth: Float) throws -> ModelEntity {
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

    static func color(hex value: UInt32) -> UIColor {
        UIColor(
            red: Double((value >> 16) & 255) / 255, green: Double((value >> 8) & 255) / 255,
            blue: Double(value & 255) / 255, alpha: 1)
    }

    static func foliageMaterials(dark: Bool) -> [[any RealityKit.Material]] {
        let palettes: [[UInt32]] =
            dark
            ? [
                [0x204637, 0x305D46, 0x4E7D5E, 0x74A57A], [0x274D35, 0x386544, 0x608B5E, 0x8BB47A],
                [0x193F37, 0x295A4B, 0x467D67, 0x69A28A],
            ]
            : [
                [0x376E42, 0x548B4A, 0x78AF5E, 0xA8CE78], [0x44743C, 0x65924A, 0x8BBB61, 0xBDD982],
                [0x2B6848, 0x468A57, 0x6AAD70, 0x9BCB8C],
            ]
        return palettes.map { colors in
            colors.map { SimpleMaterial(color: color(hex: $0), roughness: 1, isMetallic: false) }
        }
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
