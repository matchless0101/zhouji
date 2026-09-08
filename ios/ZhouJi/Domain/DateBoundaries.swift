import Foundation

enum DateBoundaries {
    static func day(containing date: Date, calendar: Calendar = .current) -> DateInterval {
        calendar.dateInterval(of: .day, for: date)
            ?? DateInterval(start: date, duration: 86_400)
    }

    static func mondayWeek(containing date: Date, calendar: Calendar = .current) -> DateInterval {
        var mondayCalendar = calendar
        mondayCalendar.firstWeekday = 2
        mondayCalendar.minimumDaysInFirstWeek = 4

        return mondayCalendar.dateInterval(of: .weekOfYear, for: date)
            ?? DateInterval(start: date, duration: 604_800)
    }

    static func overlapDuration(
        of interval: TimingInterval,
        with boundary: DateInterval
    ) -> TimeInterval {
        let start = max(interval.startedAt, boundary.start)
        let end = min(interval.endedAt, boundary.end)
        return max(0, end.timeIntervalSince(start))
    }
}

