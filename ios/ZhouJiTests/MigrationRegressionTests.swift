import Foundation
import SwiftData
import Testing
@testable import ZhouJi

/// Regression suite for data that was created under earlier product versions (V1–V3).
@MainActor
struct MigrationRegressionTests {
    @Test
    func v1TasksAndTimingRemainUsableForCompletionTimerAndStatistics() throws {
        let context = try makeContext()
        let calendar = Calendar.current
        let seed = try LegacyDataFixtures.seedV1(in: context, calendar: calendar)

        #expect(GoalService.progress(for: Goal(name: "临时")).total == 0)
        #expect(seed.pending.goal == nil)
        #expect(seed.session.taskTitleSnapshot == "整理开题资料")

        try TaskService.setCompleted(seed.pending, completed: true, in: context)
        #expect(seed.pending.isCompleted)

        let now = Date.now
        let snapshot = StatisticsService.snapshot(
            tasks: [seed.pending, seed.completed],
            sessions: [seed.session],
            now: now,
            calendar: calendar
        )
        #expect(snapshot.completedToday == 2)
        #expect(snapshot.secondsToday == 600)
        #expect(snapshot.goalTimesThisWeek.isEmpty)
    }

    @Test
    func v2GoalProgressIgnoresSoftDeletedTasksAndLegacyScopeIconResolves() throws {
        let context = try makeContext()
        let seed = try LegacyDataFixtures.seedV2(in: context)

        let progress = GoalService.progress(for: seed.goal)
        #expect(progress.completed == 1)
        #expect(progress.total == 2)
        #expect(seed.deletedTask.deletedAt != nil)
        #expect(seed.goal.iconName == GoalIcon.scope.rawValue)
        #expect(seed.goal.displayIconName == GoalIcon.book.rawValue)
        #expect(seed.goal.iconName == GoalIcon.scope.rawValue)

        try GoalService.softDelete(seed.goal, in: context)
        #expect(seed.v1.pending.goal == nil)
        #expect(seed.v1.session.goalIDSnapshot == nil)
    }

    @Test
    func v3CrossMidnightSessionsSplitByLocalDayAndRunningSessionRestores() throws {
        let context = try makeContext()
        let calendar = shanghaiCalendar
        // Seed against Shanghai calendar boundaries used by production stats.
        let seed = try seedV3Shanghai(context: context, calendar: calendar)
        let noon = try #require(calendar.date(from: DateComponents(year: 2026, month: 9, day: 9, hour: 12)))

        let tasks = try context.fetch(FetchDescriptor<TodoTask>())
        let sessions = try context.fetch(FetchDescriptor<TimingSession>())
        let snapshot = StatisticsService.snapshot(
            tasks: tasks,
            sessions: sessions.filter { $0.state == .finished },
            now: noon,
            calendar: calendar
        )
        #expect(snapshot.secondsThisWeek == 600 + 3_600)
        #expect(seed.crossMidnight.goalNameSnapshot == "完成毕业论文")

        let timer = TimerController(nowProvider: { noon })
        timer.configure(with: context)
        #expect(timer.activeSession?.id == seed.running.id)
        #expect(timer.isRunning)
    }

    @Test
    func backupRoundTripKeepsLegacySnapshotFacts() throws {
        let context = try makeContext()
        let seed = try LegacyDataFixtures.seedV3(in: context)
        let document = try BackupStore.exportDocument(from: context)
        let data = try BackupStore.encode(document)
        let decoded = try BackupStore.decode(data)

        let empty = try makeContext()
        _ = try BackupStore.restore(decoded, in: empty)
        let restoredSession = try #require(empty.fetch(FetchDescriptor<TimingSession>()).first {
            $0.id == seed.crossMidnight.id
        })
        #expect(restoredSession.goalIDSnapshot == seed.v2.goal.id)
        #expect(restoredSession.goalNameSnapshot == "完成毕业论文")
        #expect(restoredSession.accumulatedSeconds == 2 * 3_600)
    }

    private func seedV3Shanghai(context: ModelContext, calendar: Calendar) throws -> LegacyDataFixtures.V3Seed {
        let goal = Goal(name: "完成毕业论文", iconName: GoalIcon.scope.rawValue, createdAt: Date(timeIntervalSince1970: 0))
        context.insert(goal)
        let pending = TodoTask(title: "整理开题资料", createdAt: Date(timeIntervalSince1970: 1_000), goal: goal)
        let completed = TodoTask(
            title: "写摘要",
            createdAt: Date(timeIntervalSince1970: 2_000),
            completedAt: Date(timeIntervalSince1970: 2_300),
            goal: goal
        )
        context.insert(pending)
        context.insert(completed)

        let start = try #require(calendar.date(from: DateComponents(year: 2026, month: 9, day: 8, hour: 23, minute: 30)))
        let end = try #require(calendar.date(from: DateComponents(year: 2026, month: 9, day: 9, hour: 0, minute: 30)))
        let cross = TimingSession(
            taskID: completed.id,
            taskTitleSnapshot: completed.title,
            goalIDSnapshot: goal.id,
            goalNameSnapshot: goal.name,
            startedAt: start,
            endedAt: end,
            activeIntervals: [TimingInterval(startedAt: start, endedAt: end)],
            accumulatedSeconds: 3_600,
            state: .finished
        )
        let v1SessionStart = try #require(calendar.date(from: DateComponents(year: 2026, month: 9, day: 9, hour: 8)))
        let v1SessionEnd = try #require(calendar.date(from: DateComponents(year: 2026, month: 9, day: 9, hour: 8, minute: 10)))
        let finished = TimingSession(
            taskID: pending.id,
            taskTitleSnapshot: pending.title,
            startedAt: v1SessionStart,
            endedAt: v1SessionEnd,
            activeIntervals: [TimingInterval(startedAt: v1SessionStart, endedAt: v1SessionEnd)],
            accumulatedSeconds: 600,
            state: .finished
        )
        let runningStart = try #require(calendar.date(from: DateComponents(year: 2026, month: 9, day: 9, hour: 10)))
        let running = TimingSession(
            taskID: pending.id,
            taskTitleSnapshot: pending.title,
            goalIDSnapshot: goal.id,
            goalNameSnapshot: goal.name,
            startedAt: runningStart,
            runningStartedAt: runningStart,
            state: .running
        )
        context.insert(cross)
        context.insert(finished)
        context.insert(running)
        try context.save()

        let v1 = LegacyDataFixtures.V1Seed(pending: pending, completed: completed, session: finished)
        let deleted = TodoTask(
            title: "废弃提纲",
            createdAt: pending.createdAt,
            deletedAt: pending.createdAt.addingTimeInterval(400),
            goal: goal
        )
        context.insert(deleted)
        try context.save()
        let v2 = LegacyDataFixtures.V2Seed(v1: v1, goal: goal, doneTask: completed, deletedTask: deleted)
        return LegacyDataFixtures.V3Seed(v2: v2, crossMidnight: cross, running: running)
    }

    private var shanghaiCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai") ?? .current
        calendar.firstWeekday = 2
        calendar.minimumDaysInFirstWeek = 4
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
