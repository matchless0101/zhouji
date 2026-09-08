import Foundation
import SwiftData
import Testing
@testable import ZhouJi

@MainActor
struct TaskServiceTests {
    @Test
    func taskLifecyclePersistsCompletionAndSoftDeletion() throws {
        let context = try makeContext()
        let createdAt = Date(timeIntervalSince1970: 1_000)
        let completedAt = createdAt.addingTimeInterval(60)

        let task = try TaskService.create(
            title: "  写论文第三章  ",
            at: createdAt,
            in: context
        )
        #expect(task.title == "写论文第三章")
        #expect(task.completedAt == nil)

        try TaskService.setCompleted(task, completed: true, at: completedAt, in: context)
        #expect(task.completedAt == completedAt)

        try TaskService.setCompleted(task, completed: false, in: context)
        #expect(task.completedAt == nil)

        try TaskService.softDelete(task, at: completedAt, in: context)
        #expect(task.deletedAt == completedAt)

        try TaskService.restore(task, in: context)
        #expect(task.deletedAt == nil)
    }

    @Test
    func emptyTaskTitleIsRejected() throws {
        let context = try makeContext()

        #expect(throws: TaskValidationError.self) {
            try TaskService.create(title: "   \n", in: context)
        }
    }

    @Test
    func createdTaskKeepsItsSelectedGoal() throws {
        let context = try makeContext()
        let goal = try GoalService.create(name: "完成毕业论文", in: context)

        let task = try TaskService.create(
            title: "写论文摘要",
            goal: goal,
            in: context
        )

        #expect(task.goal?.id == goal.id)
        #expect(goal.tasks.contains { $0.id == task.id })
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
