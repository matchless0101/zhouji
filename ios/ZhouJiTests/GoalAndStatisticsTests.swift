import Foundation
import SwiftData
import Testing
@testable import ZhouJi

@MainActor
struct GoalAndStatisticsTests {
    @Test
    func goalProgressIgnoresDeletedTasksAndGoalDeletionKeepsTasks() throws {
        let context = try makeContext()
        let goal = try GoalService.create(name: " 完成毕业论文 ", in: context)
        let completed = try TaskService.create(title: "写摘要", goal: goal, in: context)
        let pending = try TaskService.create(title: "校对正文", goal: goal, in: context)
        let deleted = try TaskService.create(title: "废弃提纲", goal: goal, in: context)
        let dayStart = Calendar.current.startOfDay(for: .now)
        let sessionStart = dayStart.addingTimeInterval(3_600)
        let now = sessionStart.addingTimeInterval(600)
        let historicalSession = TimingSession(
            taskID: completed.id,
            taskTitleSnapshot: completed.title,
            goalIDSnapshot: goal.id,
            goalNameSnapshot: goal.name,
            startedAt: sessionStart,
            endedAt: now,
            activeIntervals: [TimingInterval(startedAt: sessionStart, endedAt: now)],
            accumulatedSeconds: 600,
            state: .finished
        )
        context.insert(historicalSession)
        try context.save()

        try TaskService.setCompleted(completed, completed: true, in: context)
        try TaskService.softDelete(deleted, in: context)

        #expect(goal.name == "完成毕业论文")
        #expect(GoalService.progress(for: goal) == GoalProgress(completed: 1, total: 2))

        try TaskService.restore(deleted, in: context)
        #expect(GoalService.progress(for: goal) == GoalProgress(completed: 1, total: 3))

        try GoalService.softDelete(goal, in: context)

        #expect(goal.deletedAt != nil)
        #expect(completed.goal == nil)
        #expect(pending.goal == nil)
        #expect(deleted.goal == nil)
        #expect(historicalSession.goalIDSnapshot == goal.id)
        #expect(historicalSession.goalNameSnapshot == "完成毕业论文")

        let statisticsAfterDeletion = StatisticsService.snapshot(
            tasks: [completed, pending, deleted],
            sessions: [historicalSession],
            now: now
        )
        #expect(statisticsAfterDeletion.secondsToday == 600)
        #expect(statisticsAfterDeletion.goalTimesThisWeek == [
            GoalTimeSummary(id: goal.id, name: "完成毕业论文", seconds: 600)
        ])

        let tasks = try context.fetch(FetchDescriptor<TodoTask>())
        #expect(tasks.count == 3)
    }

    @Test
    func statisticsSplitTimeAtLocalMidnightAndUseGoalSnapshots() throws {
        let calendar = shanghaiCalendar
        let now = try #require(calendar.date(from: DateComponents(
            year: 2026,
            month: 9,
            day: 9,
            hour: 12
        )))
        let intervalStart = try #require(calendar.date(from: DateComponents(
            year: 2026,
            month: 9,
            day: 8,
            hour: 23,
            minute: 30
        )))
        let intervalEnd = try #require(calendar.date(from: DateComponents(
            year: 2026,
            month: 9,
            day: 9,
            hour: 0,
            minute: 30
        )))
        let completedAt = try #require(calendar.date(from: DateComponents(
            year: 2026,
            month: 9,
            day: 9,
            hour: 9
        )))

        let task = TodoTask(
            title: "写论文",
            createdAt: intervalStart,
            completedAt: completedAt,
            deletedAt: completedAt.addingTimeInterval(60)
        )
        let goalID = UUID()
        let session = TimingSession(
            taskID: task.id,
            taskTitleSnapshot: task.title,
            goalIDSnapshot: goalID,
            goalNameSnapshot: "毕业论文",
            startedAt: intervalStart,
            endedAt: intervalEnd,
            activeIntervals: [TimingInterval(startedAt: intervalStart, endedAt: intervalEnd)],
            accumulatedSeconds: 3_600,
            state: .finished
        )

        let snapshot = StatisticsService.snapshot(
            tasks: [task],
            sessions: [session],
            now: now,
            calendar: calendar
        )

        #expect(snapshot.completedToday == 1)
        #expect(snapshot.completedThisWeek == 1)
        #expect(snapshot.secondsToday == 1_800)
        #expect(snapshot.secondsThisWeek == 3_600)
        #expect(snapshot.goalTimesThisWeek == [
            GoalTimeSummary(id: goalID, name: "毕业论文", seconds: 3_600)
        ])
    }

    @Test
    func emptyGoalNameIsRejected() throws {
        let context = try makeContext()

        #expect(throws: GoalValidationError.self) {
            try GoalService.create(name: "  \n", in: context)
        }
    }

    @Test
    func goalSettingsPersistTrimmedNameAndSelectedIcon() throws {
        let context = try makeContext()
        let goal = try GoalService.create(name: "阅读计划", in: context)

        try GoalService.update(
            goal,
            name: "  年度阅读  ",
            icon: .book,
            in: context
        )

        #expect(goal.name == "年度阅读")
        #expect(goal.icon == .book)
        #expect(goal.displayIconName == "book.closed")
    }

    @Test
    func goalWithoutStoredIconFallsBackToScope() {
        let goal = Goal(name: "旧目标", iconName: nil)

        #expect(goal.icon == .scope)
        #expect(goal.displayIconName == "scope")
    }

    private var shanghaiCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        calendar.firstWeekday = 2
        return calendar
    }

    private func makeContext() throws -> ModelContext {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: TodoTask.self,
            Goal.self,
            TimingSession.self,
            configurations: configuration
        )
        return ModelContext(container)
    }
}
