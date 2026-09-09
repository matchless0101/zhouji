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

    var iconSelection: GoalIcon {
        GoalIcon(rawValue: iconName ?? "") ?? .scope
    }

    var icon: GoalIcon {
        iconSelection.resolved(for: name)
    }

    var displayIconName: String {
        icon.rawValue
    }
}

enum GoalIcon: String, CaseIterable, Identifiable {
    // Keep the original default's stored value so existing goals can use automatic artwork without a migration.
    case scope
    case general = "target"
    case book = "book.closed"
    case study = "graduationcap"
    case work = "briefcase"
    case digital = "iphone"
    case exercise = "figure.run"
    case health = "heart"
    case create = "paintpalette"
    case grow = "leaf"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .scope: "自动匹配"
        case .general: "目标"
        case .book: "阅读"
        case .study: "学习"
        case .work: "工作"
        case .digital: "数字产品"
        case .exercise: "运动"
        case .health: "健康"
        case .create: "创作"
        case .grow: "成长"
        }
    }

    func resolved(for name: String) -> GoalIcon {
        guard self == .scope else { return self }

        // These local hints only choose artwork; explicit icon choices always take precedence.
        let themes: [(icon: GoalIcon, keywords: [String])] = [
            (.work, ["求职", "找工作", "招聘", "面试", "简历", "实习", "入职", "职业"]),
            (.book, ["论文", "阅读", "读书", "文献", "毕业", "写作"]),
            (.study, ["高数", "数学", "英语", "考研", "考公", "考试", "学习", "备考", "课程", "物理", "化学", "语文", "法语", "日语"]),
            (.digital, ["编程", "程序", "软件", "代码", "网站", "应用", "开发"]),
            (.exercise, ["健身", "跑步", "运动", "锻炼", "瑜伽", "骑行", "游泳", "马拉松"]),
            (.health, ["健康", "睡眠", "早睡", "饮食", "减脂", "康复"]),
            (.create, ["画画", "绘画", "设计", "创作", "摄影", "音乐", "插画"]),
            (.grow, ["成长", "习惯", "冥想", "花草", "种植", "园艺"])
        ]
        if let theme = themes.first(where: { theme in
            theme.keywords.contains(where: { name.localizedStandardContains($0) })
        }) {
            return theme.icon
        }
        if name.range(of: #"\b(?:ios|swift|swiftui|app|android|python|java|web)\b"#,
                      options: [.regularExpression, .caseInsensitive]) != nil {
            return .digital
        }
        return .general
    }
}
