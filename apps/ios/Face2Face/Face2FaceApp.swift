import SwiftUI

@main
struct Face2FaceApp: App {
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
                    ContentView()
                        .tabItem { Label("Account", systemImage: "person.crop.circle") }
                }
            #else
                ContentView()
            #endif
        }
    }
}
