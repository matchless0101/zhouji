import Foundation
import Testing
@testable import ZhouJi

struct TimerMathTests {
    @Test
    func elapsedAddsCurrentRunningInterval() {
        let start = Date(timeIntervalSince1970: 1_000)
        let now = start.addingTimeInterval(35)

        let elapsed = TimerMath.elapsed(
            accumulatedSeconds: 20,
            runningStartedAt: start,
            now: now
        )

        #expect(elapsed == 55)
    }

    @Test
    func elapsedNeverBecomesNegativeWhenClockMovesBackward() {
        let start = Date(timeIntervalSince1970: 1_000)
        let earlier = start.addingTimeInterval(-10)

        let elapsed = TimerMath.elapsed(
            accumulatedSeconds: 0,
            runningStartedAt: start,
            now: earlier
        )

        #expect(elapsed == 0)
    }

    @Test
    func durationFormatsAsClockTime() {
        #expect(TimerMath.formattedDuration(3_661.9) == "01:01:01")
    }
}

