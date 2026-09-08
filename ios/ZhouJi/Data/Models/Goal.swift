import Foundation
import SwiftData

@Model
final class Goal {
    @Attribute(.unique) var id: UUID
    var name: String
    var iconName: String?
    var createdAt: Date
    var deletedAt: Date?
    @Relationship(deleteRule: .nullify, inverse: \TodoTask.goal)
    var tasks: [TodoTask]

    init(
        id: UUID = UUID(),
        name: String,
        iconName: String? = GoalIcon.scope.rawValue,
        createdAt: Date = .now,
        deletedAt: Date? = nil,
        tasks: [TodoTask] = []
    ) {
        self.id = id
        self.name = name
        self.iconName = iconName
        self.createdAt = createdAt
        self.deletedAt = deletedAt
        self.tasks = tasks
    }

    var icon: GoalIcon {
        GoalIcon(rawValue: iconName ?? "") ?? .scope
    }

    var displayIconName: String {
        icon.rawValue
    }
}

enum GoalIcon: String, CaseIterable, Identifiable {
    case scope
    case book = "book.closed"
    case study = "graduationcap"
    case work = "briefcase"
    case exercise = "figure.run"
    case health = "heart"
    case create = "paintpalette"
    case grow = "leaf"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .scope: "目标"
        case .book: "阅读"
        case .study: "学习"
        case .work: "工作"
        case .exercise: "运动"
        case .health: "健康"
        case .create: "创作"
        case .grow: "成长"
        }
    }
}
