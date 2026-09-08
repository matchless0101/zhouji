import Foundation
import SwiftData

@Model
final class TodoTask {
    @Attribute(.unique) var id: UUID
    var title: String
    var createdAt: Date
    var completedAt: Date?
    var deletedAt: Date?
    var goal: Goal?

    init(
        id: UUID = UUID(),
        title: String,
        createdAt: Date = .now,
        completedAt: Date? = nil,
        deletedAt: Date? = nil,
        goal: Goal? = nil
    ) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.completedAt = completedAt
        self.deletedAt = deletedAt
        self.goal = goal
    }

    var isCompleted: Bool {
        completedAt != nil
    }
}
