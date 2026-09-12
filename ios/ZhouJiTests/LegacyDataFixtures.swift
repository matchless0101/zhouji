import Foundation
import SwiftData
@testable import ZhouJi

/// Seeds historical-shaped local data for migration regression.
/// Mirrors facts that exist from earlier product versions without inventing a new store schema.
@MainActor
enum LegacyDataFixtures {
    enum FixtureError: Error {
        case invalidCalendar
    }

    struct V1Seed {
        let pending: TodoTask
        let completed: TodoTask
        let session: TimingSession
    }

    struct V2Seed {
        let v1: V1Seed
        let goal: Goal
        let doneTask: TodoTask
        let deletedTask: TodoTask
    }

    struct V3Seed {
        let v2: V2Seed
        let crossMidnight: TimingSession
        let running: TimingSession
    }

    /// V1-shaped: tasks and finished timing only, no goals.
    static func seedV1(in context: ModelContext, calendar: Calendar = .current) throws -> V1Seed {
        let dayStart = calendar.startOfDay(for: .now)
        let pending = TodoTask(title: "整理开题资料", createdAt: dayStart.addingTimeInterval(8 * 3_600))
        let completed = TodoTask(
            title: "晨间阅读",
            createdAt: dayStart.addingTimeInterval(7 * 3_600),
            completedAt: dayStart.addingTimeInterval(9 * 3_600)
        )
        context.insert(pending)
        context.insert(completed)

        let start = dayStart.addingTimeInterval(10 * 3_600)
        let end = dayStart.addingTimeInterval(10 * 3_600 + 600)
        let session = TimingSession(
            taskID: pending.id,
            taskTitleSnapshot: pending.title,
            startedAt: start,
            endedAt: end,
            activeIntervals: [TimingInterval(startedAt: start, endedAt: end)],
            accumulatedSeconds: 600,
            state: .finished
        )
        context.insert(session)
        try context.save()
        return V1Seed(pending: pending, completed: completed, session: session)
    }

    /// V2-shaped: goals, assignment, soft-delete, progress.
    static func seedV2(in context: ModelContext, calendar: Calendar = .current) throws -> V2Seed {
        let v1 = try seedV1(in: context, calendar: calendar)
        // Legacy default icon value kept so automatic artwork can resolve without rewriting storage.
        let goal = Goal(
            name: "完成毕业论文",
            iconName: GoalIcon.scope.rawValue,
            createdAt: v1.pending.createdAt.addingTimeInterval(-100)
        )
        context.insert(goal)
        v1.pending.goal = goal

        let doneTask = TodoTask(
            title: "写摘要",
            createdAt: v1.pending.createdAt,
            completedAt: v1.pending.createdAt.addingTimeInterval(300),
            goal: goal
        )
        let deletedTask = TodoTask(
            title: "废弃提纲",
            createdAt: v1.pending.createdAt,
            deletedAt: v1.pending.createdAt.addingTimeInterval(400),
            goal: goal
        )
        context.insert(doneTask)
        context.insert(deletedTask)
        try context.save()
        return V2Seed(v1: v1, goal: goal, doneTask: doneTask, deletedTask: deletedTask)
    }

    /// V3-shaped: goal snapshots, cross-day interval, interrupted running session.
    static func seedV3(in context: ModelContext, calendar: Calendar = .current) throws -> V3Seed {
        let v2 = try seedV2(in: context, calendar: calendar)
        guard let yesterdayNoon = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: .now))?.addingTimeInterval(12 * 3_600) else {
            throw FixtureError.invalidCalendar
        }
        let crossMidnight = TimingSession(
            taskID: v2.doneTask.id,
            taskTitleSnapshot: v2.doneTask.title,
            goalIDSnapshot: v2.goal.id,
            goalNameSnapshot: v2.goal.name,
            startedAt: yesterdayNoon,
            endedAt: yesterdayNoon.addingTimeInterval(2 * 3_600),
            activeIntervals: [TimingInterval(startedAt: yesterdayNoon, endedAt: yesterdayNoon.addingTimeInterval(2 * 3_600))],
            accumulatedSeconds: 2 * 3_600,
            state: .finished
        )
        let runningStart = calendar.startOfDay(for: .now).addingTimeInterval(8 * 3_600)
        let running = TimingSession(
            taskID: v2.v1.pending.id,
            taskTitleSnapshot: v2.v1.pending.title,
            goalIDSnapshot: v2.goal.id,
            goalNameSnapshot: v2.goal.name,
            startedAt: runningStart,
            runningStartedAt: runningStart,
            state: .running
        )
        context.insert(crossMidnight)
        context.insert(running)
        try context.save()
        return V3Seed(v2: v2, crossMidnight: crossMidnight, running: running)
    }
}
