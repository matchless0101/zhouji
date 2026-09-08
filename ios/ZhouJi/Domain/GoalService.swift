import Foundation
import SwiftData

enum GoalValidationError: LocalizedError {
    case emptyName

    var errorDescription: String? {
        switch self {
        case .emptyName:
            return "目标名称不能为空。"
        }
    }
}

struct GoalProgress: Equatable {
    let completed: Int
    let total: Int

    var fraction: Double {
        guard total > 0 else { return 0 }
        return Double(completed) / Double(total)
    }

    var percentage: Int {
        Int((fraction * 100).rounded())
    }
}

@MainActor
enum GoalService {
    static func create(
        name: String,
        icon: GoalIcon = .scope,
        at date: Date = .now,
        in context: ModelContext
    ) throws -> Goal {
        let normalizedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedName.isEmpty else {
            throw GoalValidationError.emptyName
        }

        let goal = Goal(name: normalizedName, iconName: icon.rawValue, createdAt: date)
        context.insert(goal)
        do {
            try context.save()
        } catch {
            context.delete(goal)
            throw error
        }
        return goal
    }

    static func update(
        _ goal: Goal,
        name: String,
        icon: GoalIcon,
        in context: ModelContext
    ) throws {
        let normalizedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedName.isEmpty else {
            throw GoalValidationError.emptyName
        }

        let previousName = goal.name
        let previousIconName = goal.iconName
        goal.name = normalizedName
        goal.iconName = icon.rawValue

        do {
            try context.save()
        } catch {
            goal.name = previousName
            goal.iconName = previousIconName
            throw error
        }
    }

    static func progress(for goal: Goal) -> GoalProgress {
        let visibleTasks = goal.tasks.filter { $0.deletedAt == nil }
        return GoalProgress(
            completed: visibleTasks.filter(\.isCompleted).count,
            total: visibleTasks.count
        )
    }

    static func softDelete(
        _ goal: Goal,
        at date: Date = .now,
        in context: ModelContext
    ) throws {
        let previousDeletedAt = goal.deletedAt
        let assignedTasks = goal.tasks

        goal.deletedAt = date
        for task in assignedTasks {
            task.goal = nil
        }

        do {
            try context.save()
        } catch {
            goal.deletedAt = previousDeletedAt
            for task in assignedTasks {
                task.goal = goal
            }
            throw error
        }
    }
}
