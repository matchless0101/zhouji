import Foundation
import SwiftData

enum BackupError: LocalizedError {
    case unsupportedFormat
    case unsupportedSchema(found: Int)
    case emptyDocument
    case invalidContent(String)
    case importFailed(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedFormat:
            "这不是粥记备份文件。"
        case .unsupportedSchema(let found):
            "备份版本过新（\(found)），请升级 App 后再恢复。"
        case .emptyDocument:
            "备份文件为空，没有可恢复的数据。"
        case .invalidContent(let reason):
            "备份内容不完整：\(reason)"
        case .importFailed(let reason):
            "恢复失败：\(reason)"
        }
    }
}

struct BackupRestorePreview: Equatable {
    let goalsInsert: Int
    let goalsUpdate: Int
    let tasksInsert: Int
    let tasksUpdate: Int
    let sessionsInsert: Int
    let sessionsUpdate: Int

    var summary: String {
        "将新增 \(goalsInsert) 个目标、\(tasksInsert) 条任务、\(sessionsInsert) 段计时；更新 \(goalsUpdate) 个目标、\(tasksUpdate) 条任务、\(sessionsUpdate) 段计时。"
    }
}

struct BackupRestoreResult: Equatable {
    let preview: BackupRestorePreview
    let verifiedGoalCount: Int
    let verifiedTaskCount: Int
    let verifiedSessionCount: Int

    var summary: String {
        "已恢复并通过校验：\(verifiedGoalCount) 个目标、\(verifiedTaskCount) 条任务、\(verifiedSessionCount) 段计时。"
    }
}

/// Versioned local backup. Independent of cloud sync; CSV is not a restore source.
@MainActor
enum BackupStore {
    nonisolated static let schemaVersion = 1
    nonisolated static let formatIdentifier = "zhouji-backup"

    static func exportDocument(
        from context: ModelContext,
        applicationVersion: String = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0",
        exportedAt: Date = .now
    ) throws -> ZhouJiBackupDocument {
        let goals = try context.fetch(FetchDescriptor<Goal>())
        let tasks = try context.fetch(FetchDescriptor<TodoTask>())
        let sessions = try context.fetch(FetchDescriptor<TimingSession>())
        return ZhouJiBackupDocument(
            schemaVersion: schemaVersion,
            format: formatIdentifier,
            exportedAt: exportedAt,
            applicationVersion: applicationVersion,
            goals: goals.map(BackupGoal.init),
            tasks: tasks.map(BackupTask.init),
            timingSessions: sessions.map(BackupTimingSession.init)
        )
    }

    nonisolated static func encode(_ document: ZhouJiBackupDocument) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(document)
    }

    nonisolated static func decode(_ data: Data) throws -> ZhouJiBackupDocument {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let document: ZhouJiBackupDocument
        do {
            document = try decoder.decode(ZhouJiBackupDocument.self, from: data)
        } catch {
            throw BackupError.unsupportedFormat
        }
        guard document.format == formatIdentifier else { throw BackupError.unsupportedFormat }
        guard document.schemaVersion <= schemaVersion else {
            throw BackupError.unsupportedSchema(found: document.schemaVersion)
        }
        guard !document.goals.isEmpty || !document.tasks.isEmpty || !document.timingSessions.isEmpty else {
            throw BackupError.emptyDocument
        }
        try validate(document)
        return document
    }

    static func preview(
        _ document: ZhouJiBackupDocument,
        in context: ModelContext
    ) throws -> BackupRestorePreview {
        let existingGoals = Set(try context.fetch(FetchDescriptor<Goal>()).map(\.id))
        let existingTasks = Set(try context.fetch(FetchDescriptor<TodoTask>()).map(\.id))
        let existingSessions = Set(try context.fetch(FetchDescriptor<TimingSession>()).map(\.id))

        var goalsInsert = 0, goalsUpdate = 0
        for goal in document.goals {
            if existingGoals.contains(goal.id) { goalsUpdate += 1 } else { goalsInsert += 1 }
        }
        var tasksInsert = 0, tasksUpdate = 0
        for task in document.tasks {
            if existingTasks.contains(task.id) { tasksUpdate += 1 } else { tasksInsert += 1 }
        }
        var sessionsInsert = 0, sessionsUpdate = 0
        for session in document.timingSessions {
            if existingSessions.contains(session.id) { sessionsUpdate += 1 } else { sessionsInsert += 1 }
        }

        return BackupRestorePreview(
            goalsInsert: goalsInsert,
            goalsUpdate: goalsUpdate,
            tasksInsert: tasksInsert,
            tasksUpdate: tasksUpdate,
            sessionsInsert: sessionsInsert,
            sessionsUpdate: sessionsUpdate
        )
    }

    /// Upsert by stable id. Does not delete local rows missing from the file.
    static func restore(
        _ document: ZhouJiBackupDocument,
        in context: ModelContext
    ) throws -> BackupRestoreResult {
        let preview = try preview(document, in: context)

        var goalsByID: [UUID: Goal] = [:]
        for goal in try context.fetch(FetchDescriptor<Goal>()) { goalsByID[goal.id] = goal }
        var tasksByID: [UUID: TodoTask] = [:]
        for task in try context.fetch(FetchDescriptor<TodoTask>()) { tasksByID[task.id] = task }
        var sessionsByID: [UUID: TimingSession] = [:]
        for session in try context.fetch(FetchDescriptor<TimingSession>()) { sessionsByID[session.id] = session }

        var goalModels: [UUID: Goal] = [:]
        for dto in document.goals {
            let model = goalsByID[dto.id]
                ?? Goal(id: dto.id, name: dto.name, iconName: dto.iconName, createdAt: dto.createdAt)
            model.name = dto.name
            model.iconName = dto.iconName
            model.createdAt = dto.createdAt
            model.deletedAt = dto.deletedAt
            if goalsByID[dto.id] == nil {
                context.insert(model)
            }
            goalModels[dto.id] = model
        }

        for dto in document.tasks {
            let model = tasksByID[dto.id]
                ?? TodoTask(id: dto.id, title: dto.title, createdAt: dto.createdAt)
            model.title = dto.title
            model.createdAt = dto.createdAt
            model.completedAt = dto.completedAt
            model.deletedAt = dto.deletedAt
            if let goalID = dto.goalID {
                guard let goal = goalModels[goalID] else {
                    throw BackupError.invalidContent("任务「\(dto.title)」引用了不存在的目标。")
                }
                model.goal = goal
            } else {
                model.goal = nil
            }
            if tasksByID[dto.id] == nil {
                context.insert(model)
            }
        }

        for dto in document.timingSessions {
            let model = sessionsByID[dto.id] ?? TimingSession(
                id: dto.id,
                taskID: dto.taskID,
                taskTitleSnapshot: dto.taskTitleSnapshot,
                goalIDSnapshot: dto.goalIDSnapshot,
                goalNameSnapshot: dto.goalNameSnapshot,
                startedAt: dto.startedAt,
                endedAt: dto.endedAt,
                activeIntervals: dto.activeIntervals,
                accumulatedSeconds: dto.accumulatedSeconds,
                runningStartedAt: dto.runningStartedAt,
                state: dto.state
            )
            model.taskID = dto.taskID
            model.taskTitleSnapshot = dto.taskTitleSnapshot
            model.goalIDSnapshot = dto.goalIDSnapshot
            model.goalNameSnapshot = dto.goalNameSnapshot
            model.startedAt = dto.startedAt
            model.endedAt = dto.endedAt
            model.activeIntervals = dto.activeIntervals
            model.accumulatedSeconds = dto.accumulatedSeconds
            model.runningStartedAt = dto.runningStartedAt
            model.state = dto.state
            if sessionsByID[dto.id] == nil {
                context.insert(model)
            }
        }

        do {
            try context.save()
        } catch {
            throw BackupError.importFailed(error.localizedDescription)
        }

        try verify(document: document, in: context)
        return BackupRestoreResult(
            preview: preview,
            verifiedGoalCount: document.goals.count,
            verifiedTaskCount: document.tasks.count,
            verifiedSessionCount: document.timingSessions.count
        )
    }

    nonisolated private static func validate(_ document: ZhouJiBackupDocument) throws {
        var goalIDs = Set<UUID>()
        for goal in document.goals {
            if !goalIDs.insert(goal.id).inserted {
                throw BackupError.invalidContent("目标 ID 重复。")
            }
            if goal.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                throw BackupError.invalidContent("存在空目标名称。")
            }
        }

        for task in document.tasks {
            if task.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                throw BackupError.invalidContent("存在空任务名称。")
            }
            if let goalID = task.goalID, !goalIDs.contains(goalID) {
                throw BackupError.invalidContent("任务引用了备份中不存在的目标。")
            }
            if let completedAt = task.completedAt, completedAt < task.createdAt {
                throw BackupError.invalidContent("任务完成时间早于创建时间。")
            }
        }

        var taskIDs = Set(document.tasks.map(\.id))
        if taskIDs.count != document.tasks.count {
            throw BackupError.invalidContent("任务 ID 重复。")
        }

        var sessionIDs = Set<UUID>()
        for session in document.timingSessions {
            if !sessionIDs.insert(session.id).inserted {
                throw BackupError.invalidContent("计时 ID 重复。")
            }
            if session.accumulatedSeconds < 0 {
                throw BackupError.invalidContent("计时时长为负。")
            }
            for interval in session.activeIntervals where interval.duration < 0 {
                throw BackupError.invalidContent("计时区间结束早于开始。")
            }
            if session.state == .finished, session.endedAt == nil {
                throw BackupError.invalidContent("已结束计时缺少结束时间。")
            }
        }
    }

    private static func verify(document: ZhouJiBackupDocument, in context: ModelContext) throws {
        var goalsByID: [UUID: Goal] = [:]
        for goal in try context.fetch(FetchDescriptor<Goal>()) { goalsByID[goal.id] = goal }
        var tasksByID: [UUID: TodoTask] = [:]
        for task in try context.fetch(FetchDescriptor<TodoTask>()) { tasksByID[task.id] = task }
        var sessionsByID: [UUID: TimingSession] = [:]
        for session in try context.fetch(FetchDescriptor<TimingSession>()) { sessionsByID[session.id] = session }

        for dto in document.goals where goalsByID[dto.id] == nil {
            throw BackupError.importFailed("目标未写入。")
        }
        for dto in document.tasks {
            guard let model = tasksByID[dto.id] else {
                throw BackupError.importFailed("任务未写入。")
            }
            if model.title != dto.title
                || model.completedAt != dto.completedAt
                || model.deletedAt != dto.deletedAt
                || model.goal?.id != dto.goalID {
                throw BackupError.importFailed("任务字段与备份不一致。")
            }
        }
        for dto in document.timingSessions {
            guard let model = sessionsByID[dto.id] else {
                throw BackupError.importFailed("计时未写入。")
            }
            if abs(model.accumulatedSeconds - dto.accumulatedSeconds) > 0.001
                || model.state != dto.state
                || model.taskID != dto.taskID
                || model.activeIntervals != dto.activeIntervals {
                throw BackupError.importFailed("计时字段与备份不一致。")
            }
        }
    }
}

// MARK: - Codable snapshot

struct ZhouJiBackupDocument: Codable, Equatable, Sendable {
    let schemaVersion: Int
    let format: String
    let exportedAt: Date
    let applicationVersion: String
    let goals: [BackupGoal]
    let tasks: [BackupTask]
    let timingSessions: [BackupTimingSession]
}

struct BackupGoal: Codable, Equatable, Sendable {
    let id: UUID
    let name: String
    let iconName: String?
    let createdAt: Date
    let deletedAt: Date?

    init(id: UUID, name: String, iconName: String?, createdAt: Date, deletedAt: Date?) {
        self.id = id
        self.name = name
        self.iconName = iconName
        self.createdAt = createdAt
        self.deletedAt = deletedAt
    }

    init(_ goal: Goal) {
        self.init(id: goal.id, name: goal.name, iconName: goal.iconName, createdAt: goal.createdAt, deletedAt: goal.deletedAt)
    }
}

struct BackupTask: Codable, Equatable, Sendable {
    let id: UUID
    let title: String
    let createdAt: Date
    let completedAt: Date?
    let deletedAt: Date?
    let goalID: UUID?

    init(id: UUID, title: String, createdAt: Date, completedAt: Date?, deletedAt: Date?, goalID: UUID?) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.completedAt = completedAt
        self.deletedAt = deletedAt
        self.goalID = goalID
    }

    init(_ task: TodoTask) {
        self.init(
            id: task.id,
            title: task.title,
            createdAt: task.createdAt,
            completedAt: task.completedAt,
            deletedAt: task.deletedAt,
            goalID: task.goal?.id
        )
    }
}

struct BackupTimingSession: Codable, Equatable, Sendable {
    let id: UUID
    let taskID: UUID
    let taskTitleSnapshot: String
    let goalIDSnapshot: UUID?
    let goalNameSnapshot: String?
    let startedAt: Date
    let endedAt: Date?
    let activeIntervals: [TimingInterval]
    let accumulatedSeconds: TimeInterval
    let runningStartedAt: Date?
    let state: TimingSessionState

    init(_ session: TimingSession) {
        id = session.id
        taskID = session.taskID
        taskTitleSnapshot = session.taskTitleSnapshot
        goalIDSnapshot = session.goalIDSnapshot
        goalNameSnapshot = session.goalNameSnapshot
        startedAt = session.startedAt
        endedAt = session.endedAt
        activeIntervals = session.activeIntervals
        accumulatedSeconds = session.accumulatedSeconds
        runningStartedAt = session.runningStartedAt
        state = session.state
    }
}
