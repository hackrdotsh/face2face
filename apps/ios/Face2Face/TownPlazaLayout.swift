import SwiftUI

/// Shared by the plaza meshes and their accessible overlays.
enum TownPlazaLayout {
    static func frame(for place: TownDestination) -> CGRect {
        switch place {
        case .encounters: CGRect(x: 28, y: 122, width: 145, height: 155)
        case .connections: CGRect(x: 224, y: 119, width: 148, height: 167)
        case .forums: CGRect(x: 27, y: 405, width: 139, height: 143)
        }
    }

    static func position(for place: TownDestination) -> CGPoint {
        switch place {
        case .encounters: CGPoint(x: 105, y: 230)
        case .connections: CGPoint(x: 299, y: 230)
        case .forums: CGPoint(x: 96, y: 502)
        }
    }

    static func resident(slot: Int, time: TimeInterval) -> TownResidentPose {
        let routes = [
            (CGPoint(x: 130, y: 340), CGPoint(x: 143, y: 404)),
            (CGPoint(x: 282, y: 317), CGPoint(x: 277, y: 390)),
            (CGPoint(x: 200, y: 470), CGPoint(x: 249, y: 463)),
        ]
        let index = min(max(slot, 0), routes.count - 1)
        let phase = ((time.isFinite ? max(0, time) : 0) / (14 + Double(index) * 3) + Double(index) * 0.25)
            .truncatingRemainder(dividingBy: 2)
        let progress = phase < 1 ? phase : 2 - phase
        let route = routes[index]
        return TownResidentPose(
            point: CGPoint(
                x: route.0.x + (route.1.x - route.0.x) * progress,
                y: route.0.y + (route.1.y - route.0.y) * progress),
            facingForward: phase < 1, standing: false)
    }
}
