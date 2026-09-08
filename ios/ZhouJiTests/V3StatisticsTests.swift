import Foundation
import Testing
@testable import ZhouJi

@MainActor
struct V3StatisticsTests {
    @Test
    func mondayBoundarySplitsWeeklyTimeAndCompletionCount() throws {
        let calendar = shanghaiCalendar
        let now = try date(2026, 9, 9, 12, calendar: calendar)
        let sundayCompletion = TodoTask(
            title: "上周任务",
            completedAt: try date(2026, 9, 6, 23, 45, calendar: calendar)
        )
        let mondayCompletion = TodoTask(
            title: "本周任务",
            completedAt: try date(2026, 9, 7, 0, 15, calendar: calendar)
        )
        let start = try date(2026, 9, 6, 23, 30, calendar: calendar)
        let end = try date(2026, 9, 7, 0, 30, calendar: calendar)
        let session = finishedSession(
            task: mondayCompletion,
            start: start,
            end: end
        )

        let snapshot = StatisticsService.snapshot(
            tasks: [sundayCompletion, mondayCompletion],
            sessions: [session],
            now: now,
            calendar: calendar
        )

        #expect(snapshot.completedToday == 0)
        #expect(snapshot.completedThisWeek == 1)
        #expect(snapshot.secondsToday == 0)
        #expect(snapshot.secondsThisWeek == 1_800)
    }

    @Test
    func unassignedAndRunningTimeEnterTotalsButOnlyGoalsAreRanked() throws {
        let calendar = shanghaiCalendar
        let now = try date(2026, 9, 9, 12, calendar: calendar)
        let baseTask = TodoTask(title: "任务")
        let thesisID = UUID()
        let exerciseID = UUID()

        let thesis = finishedSession(
            task: baseTask,
            start: try date(2026, 9, 9, 8, calendar: calendar),
            end: try date(2026, 9, 9, 9, calendar: calendar),
            goalID: thesisID,
            goalName: "论文"
        )
        let exercise = finishedSession(
            task: baseTask,
            start: try date(2026, 9, 9, 9, calendar: calendar),
            end: try date(2026, 9, 9, 11, calendar: calendar),
            goalID: exerciseID,
            goalName: "运动"
        )
        let unassigned = finishedSession(
            task: baseTask,
            start: try date(2026, 9, 9, 7, 30, calendar: calendar),
            end: try date(2026, 9, 9, 8, calendar: calendar)
        )
        let running = TimingSession(
            taskID: baseTask.id,
            taskTitleSnapshot: baseTask.title,
            goalIDSnapshot: thesisID,
            goalNameSnapshot: "论文",
            startedAt: try date(2026, 9, 9, 11, 30, calendar: calendar),
            runningStartedAt: try date(2026, 9, 9, 11, 30, calendar: calendar),
            state: .running
        )

        let snapshot = StatisticsService.snapshot(
            tasks: [],
            sessions: [thesis, exercise, unassigned, running],
            now: now,
            calendar: calendar
        )

        #expect(snapshot.secondsToday == 14_400)
        #expect(snapshot.secondsThisWeek == 14_400)
        #expect(snapshot.goalTimesThisWeek == [
            GoalTimeSummary(id: exerciseID, name: "运动", seconds: 7_200),
            GoalTimeSummary(id: thesisID, name: "论文", seconds: 5_400)
        ])
    }

    @Test
    func elapsedTimeTextUsesStableZeroAndCompactUnits() {
        #expect(ElapsedTimeText.string(for: -1) == "0分钟")
        #expect(ElapsedTimeText.string(for: 59.9) == "59秒")
        #expect(ElapsedTimeText.string(for: 60) == "1分钟")
        #expect(ElapsedTimeText.string(for: 3_600) == "1小时")
        #expect(ElapsedTimeText.string(for: 3_660) == "1小时1分")
    }

    private var shanghaiCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        calendar.firstWeekday = 2
        return calendar
    }

    private func date(
        _ year: Int,
        _ month: Int,
        _ day: Int,
        _ hour: Int,
        _ minute: Int = 0,
        calendar: Calendar
    ) throws -> Date {
        try #require(calendar.date(from: DateComponents(
            year: year,
            month: month,
            day: day,
            hour: hour,
            minute: minute
        )))
    }

    private func finishedSession(
        task: TodoTask,
        start: Date,
        end: Date,
        goalID: UUID? = nil,
        goalName: String? = nil
    ) -> TimingSession {
        TimingSession(
            taskID: task.id,
            taskTitleSnapshot: task.title,
            goalIDSnapshot: goalID,
            goalNameSnapshot: goalName,
            startedAt: start,
            endedAt: end,
            activeIntervals: [TimingInterval(startedAt: start, endedAt: end)],
            accumulatedSeconds: end.timeIntervalSince(start),
            state: .finished
        )
    }
}
