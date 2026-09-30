import Foundation

struct CalendarCompletion: Identifiable {
    let id: UUID
    let title: String
    let time: Date
    let iconName: String
}

struct CalendarTiming: Identifiable {
    let id: UUID
    let title: String
    let goalName: String?
    let time: Date
    let seconds: TimeInterval
    let state: TimingSessionState
}

struct CalendarDayFacts {
    let completions: [CalendarCompletion]
    let timings: [CalendarTiming]
    var seconds: TimeInterval { timings.reduce(0) { $0 + $1.seconds } }
    var isEmpty: Bool { completions.isEmpty && timings.isEmpty }
}

/// A read-only projection of completion dates and actual active intervals.
@MainActor
enum CalendarFactsService {
    static func monthDays(containing date: Date, calendar: Calendar = .current) -> [Date?] {
        guard let month = calendar.dateInterval(of: .month, for: date),
              let range = calendar.range(of: .day, in: .month, for: date) else { return [] }
        let leading = calendar.component(.weekday, from: month.start) - 1
        var cells = Array<Date?>(repeating: nil, count: leading)
        cells += range.map { calendar.date(byAdding: .day, value: $0 - 1, to: month.start) }
        cells += Array<Date?>(repeating: nil, count: (7 - cells.count % 7) % 7)
        return cells
    }

    static func day(_ date: Date, tasks: [TodoTask], sessions: [TimingSession],
                    now: Date = .now, calendar: Calendar = .current) -> CalendarDayFacts {
        let boundary = DateBoundaries.day(containing: date, calendar: calendar)
        let completions = tasks.compactMap { task -> CalendarCompletion? in
            guard let time = task.completedAt, time >= boundary.start, time < boundary.end else { return nil }
            return CalendarCompletion(id: task.id, title: task.title, time: time,
                                      iconName: task.goal?.displayIconName ?? "checkmark")
        }.sorted { $0.time < $1.time }
        let timings = sessions.compactMap { session -> CalendarTiming? in
            let intervals = StatisticsService.effectiveIntervals(for: session, now: now)
            let seconds = intervals.reduce(0) { $0 + DateBoundaries.overlapDuration(of: $1, with: boundary) }
            guard seconds > 0 else { return nil }
            let first = intervals.filter { DateBoundaries.overlapDuration(of: $0, with: boundary) > 0 }
                .map { max($0.startedAt, boundary.start) }.min() ?? boundary.start
            return CalendarTiming(id: session.id, title: session.taskTitleSnapshot,
                                  goalName: session.goalNameSnapshot, time: first,
                                  seconds: seconds, state: session.state)
        }.sorted { $0.time < $1.time }
        return CalendarDayFacts(completions: completions, timings: timings)
    }

    static func activityDays(tasks: [TodoTask], sessions: [TimingSession], month: Date,
                             now: Date = .now, calendar: Calendar = .current) -> Set<Date> {
        guard let boundary = calendar.dateInterval(of: .month, for: month) else { return [] }
        var days = Set(tasks.compactMap { task -> Date? in
            guard let time = task.completedAt, time >= boundary.start, time < boundary.end else { return nil }
            return calendar.startOfDay(for: time)
        })
        for session in sessions {
            for interval in StatisticsService.effectiveIntervals(for: session, now: now) {
                let end = min(interval.endedAt, boundary.end)
                var day = calendar.startOfDay(for: max(interval.startedAt, boundary.start))
                while day < end {
                    if DateBoundaries.overlapDuration(of: interval, with: DateBoundaries.day(containing: day, calendar: calendar)) > 0 {
                        days.insert(day)
                    }
                    guard let next = calendar.date(byAdding: .day, value: 1, to: day), next > day else { break }
                    day = next
                }
            }
        }
        return days
    }
}
