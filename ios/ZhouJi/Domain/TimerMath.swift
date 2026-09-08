import Foundation

enum TimerMath {
    static func elapsed(
        accumulatedSeconds: TimeInterval,
        runningStartedAt: Date?,
        now: Date
    ) -> TimeInterval {
        let runningSeconds = runningStartedAt.map {
            max(0, now.timeIntervalSince($0))
        } ?? 0

        return max(0, accumulatedSeconds + runningSeconds)
    }

    static func formattedDuration(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded(.down)))
        let hours = total / 3_600
        let minutes = (total % 3_600) / 60
        let remainingSeconds = total % 60

        return String(format: "%02d:%02d:%02d", hours, minutes, remainingSeconds)
    }
}

