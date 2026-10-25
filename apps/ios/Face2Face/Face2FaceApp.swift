import SwiftUI

@main
struct Face2FaceApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase
    @State private var walk = ConnectedDiscoveryModel.backgroundWalk
    #if DEBUG
        @State private var pocket = PocketDiscoveryModel.shared
    #endif

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active || phase == .background else { return }
            let active = phase == .active
            walk.sceneChanged(active: active)
            #if DEBUG
                pocket.sceneChanged(active: active)
            #endif
        }
    }
}
