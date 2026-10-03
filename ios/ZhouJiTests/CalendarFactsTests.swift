import Foundation
import Testing
@testable import ZhouJi

@MainActor
struct CalendarFactsTests {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return value
    }

    private func date(_ day: Int, hour: Int = 0, minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 9, day: day, hour: hour, minute: minute))!
    }

    @Test func monthGridStartsOnSundayAndIncludesEveryDay() {
        let cells = CalendarFactsService.monthDays(containing: date(15), calendar: calendar)
        #expect(cells.count == 35)
        #expect(cells.prefix(2).allSatisfy { $0 == nil })
        #expect(cells.compactMap { $0 }.count == 30)
        #expect(cells[2] == date(1))
        #expect(cells[31] == date(30))
    }

    @Test func crossMidnightTimingSplitsAndExcludesPausedGap() {
        let session = TimingSession(taskID: UUID(), taskTitleSnapshot: "读书", startedAt: date(8, hour: 23, minute: 50),
            activeIntervals: [
                TimingInterval(startedAt: date(8, hour: 23, minute: 50), endedAt: date(9, minute: 10)),
                TimingInterval(startedAt: date(9, hour: 1), endedAt: date(9, hour: 1, minute: 20))
            ], state: .finished)
        let yesterday = CalendarFactsService.day(date(8), tasks: [], sessions: [session], now: date(10), calendar: calendar)
        let today = CalendarFactsService.day(date(9), tasks: [], sessions: [session], now: date(10), calendar: calendar)
        #expect(yesterday.seconds == 600)
        #expect(today.seconds == 1_800)
        #expect(today.timings.first?.time == date(9))
        #expect(today.timings.first?.title == "读书")
    }

    @Test func runningTimeUsesNowAndDoesNotMarkFutureDays() {
        let start = date(8, hour: 23, minute: 50)
        let session = TimingSession(taskID: UUID(), taskTitleSnapshot: "跨夜投入", startedAt: start,
            runningStartedAt: start, state: .running)
        let result = CalendarFactsService.day(date(9), tasks: [], sessions: [session], now: date(9, minute: 20), calendar: calendar)
        #expect(result.seconds == 1_200)
        #expect(result.timings.first?.state == .running)
        let activity = CalendarFactsService.activityDays(tasks: [], sessions: [session], month: date(15), now: date(9, minute: 20), calendar: calendar)
        #expect(activity == Set([date(8), date(9)]))
    }

    @Test func deletedTasksAndGoalSnapshotsRemainInHistory() {
        let task = TodoTask(title: "完成小事", completedAt: date(9, hour: 8))
        task.deletedAt = date(10)
        let session = TimingSession(taskID: task.id, taskTitleSnapshot: "原任务名称", goalIDSnapshot: UUID(),
            goalNameSnapshot: "原目标", startedAt: date(9, hour: 7),
            activeIntervals: [TimingInterval(startedAt: date(9, hour: 7), endedAt: date(9, hour: 8))], state: .finished)
        let result = CalendarFactsService.day(date(9), tasks: [task], sessions: [session], now: date(10), calendar: calendar)
        #expect(result.completions.count == 1)
        #expect(result.timings.first?.title == "原任务名称")
        #expect(result.timings.first?.goalName == "原目标")
        #expect(result.seconds == 3_600)
    }

    @Test func midnightCompletionBelongsOnlyToNewDay() {
        let task = TodoTask(title: "午夜完成", completedAt: date(9))
        #expect(CalendarFactsService.day(date(8), tasks: [task], sessions: [], calendar: calendar).completions.isEmpty)
        #expect(CalendarFactsService.day(date(9), tasks: [task], sessions: [], calendar: calendar).completions.count == 1)
    }

    @Test func pausedSessionWithoutActiveTimeDoesNotMarkADay() {
        let session = TimingSession(taskID: UUID(), taskTitleSnapshot: "尚未投入", startedAt: date(9), state: .paused)
        #expect(CalendarFactsService.day(date(9), tasks: [], sessions: [session], calendar: calendar).timings.isEmpty)
        #expect(CalendarFactsService.activityDays(tasks: [], sessions: [session], month: date(9), calendar: calendar).isEmpty)
    }
    @Test func liveProjectionMatchesFactsAcrossMidnightAndKeepsHistoricalValues() {
        let task = TodoTask(title: "原名称", completedAt: date(8, hour: 8))
        let saved = TimingSession(taskID: task.id, taskTitleSnapshot: "已保存",
            startedAt: date(8, hour: 10), activeIntervals: [
                TimingInterval(startedAt: date(8, hour: 10), endedAt: date(8, hour: 11))
            ], state: .finished)
        let running = TimingSession(taskID: UUID(), taskTitleSnapshot: "跨夜",
            startedAt: date(8, hour: 23, minute: 50),
            runningStartedAt: date(8, hour: 23, minute: 50), state: .running)
        let projection = CalendarFactsService.projection(date(9), month: date(15),
            tasks: [task], sessions: [saved, running], calendar: calendar)
        for now in [date(8, hour: 23, minute: 55), date(9), date(9, minute: 20), date(10), date(30, hour: 23), calendar.date(byAdding: .month, value: 1, to: date(1))!] {
            let expected = CalendarFactsService.day(date(9), tasks: [task], sessions: [saved, running], now: now, calendar: calendar)
            let actual = projection.day(now: now)
            #expect(actual.seconds == expected.seconds)
            #expect(actual.timings.map(\.id) == expected.timings.map(\.id))
            #expect(actual.timings.map(\.time) == expected.timings.map(\.time))
            #expect(projection.activityDays(now: now) == CalendarFactsService.activityDays(tasks: [task], sessions: [saved, running], month: date(15), now: now, calendar: calendar))
        }
        // A clock tick consumes captured facts, not historical model objects.
        let historical = CalendarFactsService.projection(date(8), month: date(15),
            tasks: [task], sessions: [saved, running], calendar: calendar)
        saved.activeIntervalsData = Data()
        task.title = "已修改"
        #expect(historical.day(now: date(9, minute: 20)).seconds == 4200)
        #expect(historical.day(now: date(9, minute: 20)).completions.first?.title == "原名称")
    }

    @Test func projectionRebuildReflectsPauseResumeAndCompletionUndo() {
        let task = TodoTask(title: "完成小事", completedAt: date(9, hour: 8))
        let session = TimingSession(taskID: task.id, taskTitleSnapshot: task.title,
            startedAt: date(9, hour: 9), runningStartedAt: date(9, hour: 9), state: .running)
        let first = CalendarFactsService.projection(date(9), month: date(9), tasks: [task], sessions: [session], calendar: calendar)
        #expect(first.day(now: date(9, hour: 10)).seconds == 3600)
        session.activeIntervals = [TimingInterval(startedAt: date(9, hour: 9), endedAt: date(9, hour: 10))]
        session.state = .paused
        session.runningStartedAt = nil
        task.completedAt = nil
        let paused = CalendarFactsService.projection(date(9), month: date(9), tasks: [task], sessions: [session], calendar: calendar)
        #expect(paused.day(now: date(9, hour: 11)).seconds == 3600)
        #expect(paused.day(now: date(9, hour: 11)).completions.isEmpty)
        session.state = .running
        session.runningStartedAt = date(9, hour: 11)
        let resumed = CalendarFactsService.projection(date(9), month: date(9), tasks: [task], sessions: [session], calendar: calendar)
        #expect(resumed.day(now: date(9, hour: 12)).seconds == 7200)
        #expect(resumed.day(now: date(9, hour: 12)).timings.count == 1)
    }

    @Test func weeklyDurationProjectionMatchesFullStatisticsAcrossWeekBoundary() {
        let session = TimingSession(taskID: UUID(), taskTitleSnapshot: "跨周",
            startedAt: date(6, hour: 23), activeIntervals: [
                TimingInterval(startedAt: date(6, hour: 23), endedAt: date(7, hour: 1))
            ], runningStartedAt: date(7, hour: 2), state: .running)
        let projection = StatisticsService.weekDuration(sessions: [session], containing: date(7), calendar: calendar)
        for now in [date(7, hour: 2), date(7, hour: 3), date(14)] {
            let expected = StatisticsService.snapshot(tasks: [], sessions: [session], now: now, periodDate: date(7), calendar: calendar)
            #expect(projection.seconds(now: now) == expected.secondsThisWeek)
        }
    }

}
