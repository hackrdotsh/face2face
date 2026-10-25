import AppIntents
import WidgetKit

struct CampfirePageIntent: AppIntent {
    static let title: LocalizedStringResource = "Turn the campfire page"
    static let openAppWhenRun = false

    @Parameter(title: "Direction") var step: Int
    @Parameter(title: "Friends per page") var size: Int

    init() {}

    init(step: Int, size: Int) {
        self.step = step
        self.size = size
    }

    func perform() async throws -> some IntentResult {
        CampfireStore.advance(by: step, size: [4, 6, 10].contains(size) ? size : 6)
        WidgetCenter.shared.reloadTimelines(ofKind: "DailyBlob")
        return .result()
    }
}
