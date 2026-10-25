import Foundation
import Testing

@testable import Face2FaceCore

private let step: TimeInterval = 0.05

/// Start and end times of each showing in the first `duration` seconds.
private func showings(seed: String, duration: TimeInterval) -> [(start: TimeInterval, end: TimeInterval)] {
    var result: [(start: TimeInterval, end: TimeInterval)] = []
    var time: TimeInterval = 0
    while time < duration {
        let isShown = TownStatusBubble.visibility(seed: seed, time: time) > 0
        if isShown, result.last.map({ $0.end < time - step * 1.5 }) ?? true {
            result.append((time, time))
        } else if isShown {
            result[result.count - 1].end = time
        }
        time += step
    }
    return result
}

@Test func showsEachBubbleForFourSecondsAfterAnEightToTwentySecondGap() {
    for seed in ["peer-a", "peer-b", "peer-c", ""] {
        let shown = showings(seed: seed, duration: 300)
        #expect(shown.count >= 11)
        var previousEnd: TimeInterval = 0
        for showing in shown {
            #expect(abs(showing.end - showing.start - TownStatusBubble.shownDuration) <= step * 2)
            let gap = showing.start - previousEnd
            #expect(gap >= TownStatusBubble.gap.lowerBound - step * 2)
            #expect(gap <= TownStatusBubble.gap.upperBound + step * 2)
            previousEnd = showing.end
        }
    }
}

@Test func givesEachResidentItsOwnTiming() {
    let first = showings(seed: "peer-a", duration: 120).map(\.start)
    let second = showings(seed: "peer-b", duration: 120).map(\.start)
    #expect(first != second)
    #expect(showings(seed: "peer-a", duration: 120).map(\.start) == first)
}

@Test func fadesInAndOutAndStaysHiddenForBadTimes() {
    let start = showings(seed: "peer-a", duration: 60)[0].start
    let rising = TownStatusBubble.visibility(seed: "peer-a", time: start + 0.1)
    #expect(rising > 0 && rising < 1)
    #expect(TownStatusBubble.visibility(seed: "peer-a", time: start + 2) == 1)
    for time in [0, -5, .nan, .infinity] as [TimeInterval] {
        #expect(TownStatusBubble.visibility(seed: "peer-a", time: time) == 0)
    }
}
