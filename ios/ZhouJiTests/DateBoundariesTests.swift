import Foundation
import Testing
@testable import ZhouJi

struct DateBoundariesTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        calendar.locale = Locale(identifier: "zh_CN")
        return calendar
    }

    @Test
    func weekStartsOnMonday() throws {
        let date = try #require(
            calendar.date(from: DateComponents(year: 2026, month: 9, day: 9, hour: 12))
        )
        let week = DateBoundaries.mondayWeek(containing: date, calendar: calendar)
        let components = calendar.dateComponents([.year, .month, .day, .weekday], from: week.start)

        #expect(components.year == 2026)
        #expect(components.month == 9)
        #expect(components.day == 7)
        #expect(components.weekday == 2)
    }

    @Test
    func overlapSplitsIntervalAtDayBoundary() throws {
        let dayStart = try #require(
            calendar.date(from: DateComponents(year: 2026, month: 9, day: 7))
        )
        let boundary = DateBoundaries.day(containing: dayStart, calendar: calendar)
        let interval = TimingInterval(
            startedAt: dayStart.addingTimeInterval(-600),
            endedAt: dayStart.addingTimeInterval(900)
        )

        #expect(DateBoundaries.overlapDuration(of: interval, with: boundary) == 900)
    }
}

