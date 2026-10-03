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
    /// Capture saved history on model/date changes; subsequent ticks only project live intervals.
    static func projection(_ date: Date, month: Date, tasks: [TodoTask], sessions: [TimingSession],
                           calendar: Calendar = .current) throws -> CalendarLiveProjection {
        CalendarLiveProjection(
            savedDay: try day(date, tasks: tasks, sessions: sessions, now: .distantPast, calendar: calendar),
            savedActivity: try activityDays(tasks: tasks, sessions: sessions, month: month, now: .distantPast, calendar: calendar),
            running: sessions.compactMap { session in
                guard session.state == .running, let start = session.runningStartedAt else { return nil }
                return CalendarRunningTiming(id: session.id, title: session.taskTitleSnapshot,
                    goalName: session.goalNameSnapshot, start: start)
            },
            dayBoundary: DateBoundaries.day(containing: date, calendar: calendar),
            monthBoundary: calendar.dateInterval(of: .month, for: month), calendar: calendar)
    }

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
                    now: Date = .now, calendar: Calendar = .current) throws -> CalendarDayFacts {
        let boundary = DateBoundaries.day(containing: date, calendar: calendar)
        let completions = tasks.compactMap { task -> CalendarCompletion? in
            guard let time = task.completedAt, time >= boundary.start, time < boundary.end else { return nil }
            return CalendarCompletion(id: task.id, title: task.title, time: time,
                                      iconName: task.goal?.displayIconName ?? "checkmark")
        }.sorted { $0.time < $1.time }
        let timings = try sessions.compactMap { session -> CalendarTiming? in
            let intervals = try StatisticsService.effectiveIntervals(for: session, now: now)
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
                             now: Date = .now, calendar: Calendar = .current) throws -> Set<Date> {
        guard let boundary = calendar.dateInterval(of: .month, for: month) else { return [] }
        var days = Set(tasks.compactMap { task -> Date? in
            guard let time = task.completedAt, time >= boundary.start, time < boundary.end else { return nil }
            return calendar.startOfDay(for: time)
        })
        for session in sessions {
            for interval in try StatisticsService.effectiveIntervals(for: session, now: now) {
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

fileprivate struct CalendarRunningTiming {
    let id: UUID
    let title: String
    let goalName: String?
    let start: Date
}

@MainActor
struct CalendarLiveProjection {
    fileprivate let savedDay: CalendarDayFacts
    fileprivate let savedActivity: Set<Date>
    fileprivate let running: [CalendarRunningTiming]
    fileprivate let dayBoundary: DateInterval
    fileprivate let monthBoundary: DateInterval?
    fileprivate let calendar: Calendar

    var isRunning: Bool { !running.isEmpty }

    func day(now: Date) -> CalendarDayFacts {
        guard !running.isEmpty else { return savedDay }
        var timings = savedDay.timings
        for live in running {
            let interval = TimingInterval(startedAt: live.start, endedAt: max(live.start, now))
            let seconds = DateBoundaries.overlapDuration(of: interval, with: dayBoundary)
            guard seconds > 0 else { continue }
            let index = timings.firstIndex { $0.id == live.id }
            let saved = index.map { timings[$0] }
            let timing = CalendarTiming(id: live.id, title: live.title, goalName: live.goalName,
                time: min(saved?.time ?? .distantFuture, max(live.start, dayBoundary.start)),
                seconds: (saved?.seconds ?? 0) + seconds, state: .running)
            if let index { timings[index] = timing } else { timings.append(timing) }
        }
        timings.sort { $0.time < $1.time }
        return CalendarDayFacts(completions: savedDay.completions, timings: timings)
    }

    func activityDays(now: Date) -> Set<Date> {
        var days = savedActivity
        guard let boundary = monthBoundary else { return days }
        for live in running {
            let interval = TimingInterval(startedAt: live.start, endedAt: max(live.start, now))
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
        return days
    }
}
