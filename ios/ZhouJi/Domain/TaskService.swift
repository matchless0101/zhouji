import Foundation
import SwiftData

enum TaskValidationError: LocalizedError {
    case emptyTitle

    var errorDescription: String? {
        switch self {
        case .emptyTitle:
            "任务名称不能为空。"
        }
    }
}

@MainActor
enum TaskService {
    static func create(
        title: String,
        goal: Goal? = nil,
        at date: Date = .now,
        in context: ModelContext
    ) throws -> TodoTask {
        let normalizedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedTitle.isEmpty else {
            throw TaskValidationError.emptyTitle
        }

        let task = TodoTask(title: normalizedTitle, createdAt: date, goal: goal)
        context.insert(task)
        do {
            try context.save()
        } catch {
            context.delete(task)
            throw error
        }
        return task
    }

    static func setCompleted(
        _ task: TodoTask,
        completed: Bool,
        at date: Date = .now,
        in context: ModelContext
    ) throws {
        let previousCompletedAt = task.completedAt
        task.completedAt = completed ? date : nil
        do {
            try context.save()
        } catch {
            task.completedAt = previousCompletedAt
            throw error
        }
    }

    static func softDelete(
        _ task: TodoTask,
        at date: Date = .now,
        in context: ModelContext
    ) throws {
        let previousDeletedAt = task.deletedAt
        task.deletedAt = date
        do {
            try context.save()
        } catch {
            task.deletedAt = previousDeletedAt
            throw error
        }
    }

    static func restore(
        _ task: TodoTask,
        in context: ModelContext
    ) throws {
        let previousDeletedAt = task.deletedAt
        task.deletedAt = nil
        do {
            try context.save()
        } catch {
            task.deletedAt = previousDeletedAt
            throw error
        }
    }
}
