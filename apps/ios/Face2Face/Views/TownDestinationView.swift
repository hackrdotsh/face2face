import SwiftUI

struct TownDestinationView: View {
    let destination: TownDestination
    let session: SessionModel

    var body: some View {
        switch destination {
        case .connections: ChatsView(session: session)
        case .forums: ForumsView(session: session)
        case .encounters: RecentlyEncounteredView(session: session)
        }
    }
}
