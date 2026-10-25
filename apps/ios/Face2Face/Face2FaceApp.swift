import SwiftUI

@main
struct Face2FaceApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var walk = ConnectedDiscoveryModel.backgroundWalk
    #if DEBUG
        @State private var pocket = PocketDiscoveryModel.shared
    #endif

    var body: some Scene {
        WindowGroup {
            #if DEBUG
                TabView {
                    RootView()
                        .tabItem { Label("Account", systemImage: "person.crop.circle") }
                    NavigationStack {
                        WalkDiscoveryView(model: walk)
                    }
                    .tabItem { Label("Walk test", systemImage: "person.crop.circle.badge.clock") }
                    .badge(walk.isRunning ? "On" : nil)
                    NavigationStack {
                        ConnectedDiscoveryView()
                    }
                    .tabItem { Label("Connected test", systemImage: "person.2.wave.2") }
                    NavigationStack {
                        PocketDiscoveryView(model: pocket)
                    }
                    .tabItem { Label("Pocket test", systemImage: "figure.walk") }
                    .badge(pocket.radio.isRequested ? "On" : nil)
                    NavigationStack {
                        DiscoveryDiagnosticView()
                    }
                    .tabItem { Label("Device test", systemImage: "antenna.radiowaves.left.and.right") }
                }
            #else
                RootView()
            #endif
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
