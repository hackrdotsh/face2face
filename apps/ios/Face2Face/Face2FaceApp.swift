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
                    ContentView()
                        .tabItem { Label("Account", systemImage: "person.crop.circle") }
                }
            #else
                ContentView()
            #endif
        }
    }
}
