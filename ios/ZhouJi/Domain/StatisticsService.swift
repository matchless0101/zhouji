import Foundation

struct GoalTimeSummary: Identifiable, Equatable {
    let id: UUID
    let name: String
    let seconds: TimeInterval
}

struct StatisticsSnapshot: Equatable {
    let completedToday: Int
    let completedThisWeek: Int
    let secondsToday: TimeInterval
    let secondsThisWeek: TimeInterval
    let goalTimesThisWeek: [GoalTimeSummary]
}

@MainActor
enum StatisticsService {
    static func snapshot(
        tasks: [TodoTask],
        sessions: [TimingSession],
        now: Date = .now,
        periodDate: Date? = nil,
        calendar: Calendar = .current
    ) -> StatisticsSnapshot {
        let day = DateBoundaries.day(containing: periodDate ?? now, calendar: calendar)
        let week = DateBoundaries.mondayWeek(containing: periodDate ?? now, calendar: calendar)

        let completedToday = tasks.count { task in
            task.completedAt.map { contains($0, in: day) } ?? false
        }
        let completedThisWeek = tasks.count { task in
            task.completedAt.map { contains($0, in: week) } ?? false
        }

        var secondsToday: TimeInterval = 0
        var secondsThisWeek: TimeInterval = 0
        var goalTotals: [UUID: (name: String, seconds: TimeInterval)] = [:]

        for session in sessions {
            let intervals = effectiveIntervals(for: session, now: now)
            let daySeconds = intervals.reduce(0) {
                $0 + DateBoundaries.overlapDuration(of: $1, with: day)
            }
            let weekSeconds = intervals.reduce(0) {
                $0 + DateBoundaries.overlapDuration(of: $1, with: week)
            }

            secondsToday += daySeconds
            secondsThisWeek += weekSeconds

            if let goalID = session.goalIDSnapshot,
               let goalName = session.goalNameSnapshot,
               weekSeconds > 0 {
                let existing = goalTotals[goalID]?.seconds ?? 0
                goalTotals[goalID] = (goalName, existing + weekSeconds)
            }
        }

        let goalTimes = goalTotals
            .map { GoalTimeSummary(id: $0.key, name: $0.value.name, seconds: $0.value.seconds) }
            .sorted {
                if $0.seconds == $1.seconds {
                    return $0.name.localizedStandardCompare($1.name) == .orderedAscending
                }
                return $0.seconds > $1.seconds
            }

        return StatisticsSnapshot(
            completedToday: completedToday,
            completedThisWeek: completedThisWeek,
            secondsToday: secondsToday,
            secondsThisWeek: secondsThisWeek,
            goalTimesThisWeek: goalTimes
        )
    }

    private static func effectiveIntervals(
        for session: TimingSession,
        now: Date
    ) -> [TimingInterval] {
        var intervals = session.activeIntervals
        if session.state == .running, let runningStartedAt = session.runningStartedAt {
            intervals.append(
                TimingInterval(startedAt: runningStartedAt, endedAt: max(now, runningStartedAt))
            )
        }
        return intervals
    }

    private static func contains(_ date: Date, in interval: DateInterval) -> Bool {
        date >= interval.start && date < interval.end
    }
}


/// Comparisons use the same fact-derived totals as the main statistics cards.
enum StatisticsComparison {
    static func completed(_ current: Int, previous: Int, period: String) -> String {
        let difference = current - previous
        guard difference != 0 else { return "和\(period)一样" }
        return "比\(period)\(difference > 0 ? "多" : "少") \(abs(difference)) 件"
    }

    static func duration(_ current: TimeInterval, previous: TimeInterval, period: String) -> String {
        let difference = Int(max(0, current)) - Int(max(0, previous))
        guard difference != 0 else { return "和\(period)一样" }
        return "比\(period)\(difference > 0 ? "多" : "少") \(ElapsedTimeText.string(for: TimeInterval(abs(difference))))"
    }
}
