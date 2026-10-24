import SwiftUI

@main
struct Face2FaceApp: App {
    #if DEBUG
        @Environment(\.scenePhase) private var scenePhase
        @State private var pocket = PocketDiscoveryModel.shared
    #endif
    var body: some Scene {
        WindowGroup {
            #if DEBUG
                TabView {
                    NavigationStack {
                        DiscoveryDiagnosticView()
                    }
                    .tabItem { Label("Device test", systemImage: "antenna.radiowaves.left.and.right") }
                    NavigationStack {
                        ConnectedDiscoveryView()
                    }
                    .tabItem { Label("Connected test", systemImage: "person.2.wave.2") }
                    NavigationStack {
                        PocketDiscoveryView(model: pocket)
                    }
                    .tabItem { Label("Pocket test", systemImage: "figure.walk") }
                    .badge(pocket.radio.isRequested ? "On" : nil)
                    ContentView()
                        .tabItem { Label("Account", systemImage: "person.crop.circle") }
                }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active { pocket.sceneChanged(active: true) }
                    if phase == .background { pocket.sceneChanged(active: false) }
                }
            #else
                ContentView()
            #endif
        }
    }
}
