import Foundation
import SwiftData

enum BackupError: LocalizedError {
    case unsupportedFormat
    case unsupportedSchema(found: Int)
    case emptyDocument
    case tooLarge
    case activeTimer
    case contentChanged
    case unsupportedScope
    case protectionFailed
    case invalidContent(String)
    case importFailed(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedFormat:
            "这不是粥记备份文件。"
        case .unsupportedSchema(let found):
            "不支持此备份版本（\(found)），请使用兼容版本的粥记。"
        case .tooLarge:
            "备份文件过大，请使用不超过 32 MB 的备份。"
        case .activeTimer:
            "请先结束当前计时，再恢复备份。暂停的计时也需要先结束。"
        case .contentChanged:
            "本机数据已变化，请重新选择备份并确认恢复内容。"
        case .unsupportedScope:
            "此备份包含账户分区，当前版本仅支持恢复本机数据。"
        case .protectionFailed:
            "未能保存恢复前的保护副本，本机数据未改动。请检查可用空间后重试。"
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
    nonisolated static let schemaVersion = 2
    nonisolated static let maximumBytes = 32 * 1024 * 1024
    nonisolated static let maximumRecords = 50_000
    nonisolated static let formatIdentifier = "zhouji-backup"

    static func exportDocument(
        from context: ModelContext,
        applicationVersion: String = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0",
        exportedAt: Date = .now
    ) throws -> ZhouJiBackupDocument {
        let goals = try context.fetch(FetchDescriptor<Goal>())
        let tasks = try context.fetch(FetchDescriptor<TodoTask>())
        let sessions = try context.fetch(FetchDescriptor<TimingSession>())
        for session in sessions {
            guard TimingSessionState(rawValue: session.stateRawValue) != nil else {
                throw BackupError.invalidContent("未知计时状态。")
            }
            if !session.activeIntervalsData.isEmpty {
                guard (try? JSONDecoder().decode([TimingInterval].self, from: session.activeIntervalsData)) != nil else {
                    throw BackupError.invalidContent("计时区间无法读取。")
                }
            }
        }
        let document = ZhouJiBackupDocument(
            schemaVersion: schemaVersion,
            format: formatIdentifier,
            exportedAt: exportedAt,
            applicationVersion: applicationVersion,
            goals: goals.map(BackupGoal.init).sorted { $0.id.uuidString < $1.id.uuidString },
            tasks: tasks.map(BackupTask.init).sorted { $0.id.uuidString < $1.id.uuidString },
            timingSessions: sessions.map(BackupTimingSession.init).sorted { $0.id.uuidString < $1.id.uuidString },
            dataScope: "local"
        )
        return try prepared(document, allowEmpty: true)
    }

    nonisolated static func encode(_ document: ZhouJiBackupDocument) throws -> Data {
        try validate(document, allowEmpty: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        // v2 stores epoch seconds as Double, preserving interval precision lost by v1 ISO8601 encoding.
        encoder.dateEncodingStrategy = document.schemaVersion == 1 ? .iso8601 : .secondsSince1970
        let data = try encoder.encode(document)
        guard data.count <= maximumBytes else { throw BackupError.tooLarge }
        return data
    }

    nonisolated static func decode(_ data: Data) throws -> ZhouJiBackupDocument {
        guard data.count <= maximumBytes else { throw BackupError.tooLarge }
        struct Header: Decodable { let schemaVersion: Int; let format: String }
        let header: Header
        do { header = try JSONDecoder().decode(Header.self, from: data) }
        catch { throw BackupError.unsupportedFormat }
        guard header.format == formatIdentifier else { throw BackupError.unsupportedFormat }
        guard (1...schemaVersion).contains(header.schemaVersion) else {
            throw BackupError.unsupportedSchema(found: header.schemaVersion)
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = header.schemaVersion == 1 ? .iso8601 : .secondsSince1970
        let document: ZhouJiBackupDocument
        do { document = try decoder.decode(ZhouJiBackupDocument.self, from: data) }
        catch { throw BackupError.unsupportedFormat }
        return try prepared(document)
    }

    nonisolated static func readFile(_ url: URL) throws -> ZhouJiBackupDocument {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var data = Data()
        while let chunk = try handle.read(upToCount: min(65_536, maximumBytes + 1 - data.count)), !chunk.isEmpty {
            data.append(chunk)
            guard data.count <= maximumBytes else { throw BackupError.tooLarge }
        }
        return try decode(data)
    }

    nonisolated static func prepared(_ document: ZhouJiBackupDocument, allowEmpty: Bool = false) throws -> ZhouJiBackupDocument {
        try validate(document, allowEmpty: allowEmpty)
        var result = document
        result.timingSessions = document.timingSessions.map { original in
            var snapshot = original
            if original.state == .running, let start = original.runningStartedAt {
                snapshot.activeIntervals.append(TimingInterval(startedAt: start, endedAt: max(start, document.exportedAt)))
                snapshot.runningStartedAt = nil
                snapshot.state = .paused
            }
            // v1 rounded dates to whole seconds. Its interval facts, rather than a stale total, are authoritative.
            snapshot.accumulatedSeconds = snapshot.activeIntervals.reduce(0) { $0 + $1.duration }
            return snapshot
        }
        return result
    }

    static func ensureCanRestore(in context: ModelContext) throws {
        if try context.fetch(FetchDescriptor<TimingSession>()).contains(where: { $0.state != .finished }) {
            throw BackupError.activeTimer
        }
    }

    static func preview(
        _ document: ZhouJiBackupDocument,
        in context: ModelContext
    ) throws -> BackupRestorePreview {
        _ = try prepared(document)
        try ensureCanRestore(in: context)
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
        in context: ModelContext,
        expectedContent: ZhouJiBackupDocument? = nil,
        protectionWriter: (Data) throws -> Void = BackupSafetyStore.save,
        saveChanges: (ModelContext) throws -> Void = { try $0.save() }
    ) throws -> BackupRestoreResult {
        let document = try prepared(document)
        let preview = try preview(document, in: context)
        let before = try exportDocument(from: context)
        if let expectedContent,
           before.goals != expectedContent.goals || before.tasks != expectedContent.tasks
            || before.timingSessions != expectedContent.timingSessions {
            throw BackupError.contentChanged
        }
        // Establish the rollback boundary before making any import mutations.
        try context.save()
        do { try protectionWriter(encode(before)) }
        catch { throw BackupError.protectionFailed }
        let wasAutosaveEnabled = context.autosaveEnabled
        context.autosaveEnabled = false
        defer { context.autosaveEnabled = wasAutosaveEnabled }
        do {
            try apply(document, in: context)
            try verify(document: document, in: context)
            try saveChanges(context)
        } catch {
            // SwiftData rollback can leave retained @Model instances exposing edited values.
            // Reset those values while the original instances are still registered, then discard pending writes.
            do { try apply(before, in: context) }
            catch {
                context.rollback()
                throw BackupError.importFailed("恢复已中断，保护副本已保存。请重新打开 App 后检查本机数据。")
            }
            context.rollback()
            throw BackupError.importFailed("未完成恢复，本机数据已回退到恢复前。")
        }
        return BackupRestoreResult(
            preview: preview,
            verifiedGoalCount: document.goals.count,
            verifiedTaskCount: document.tasks.count,
            verifiedSessionCount: document.timingSessions.count
        )
    }

    private static func apply(_ document: ZhouJiBackupDocument, in context: ModelContext) throws {

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

    }

    nonisolated private static func validate(_ document: ZhouJiBackupDocument, allowEmpty: Bool) throws {
        guard document.format == formatIdentifier else { throw BackupError.unsupportedFormat }
        guard (1...schemaVersion).contains(document.schemaVersion) else {
            throw BackupError.unsupportedSchema(found: document.schemaVersion)
        }
        guard document.dataScope == "local" || (document.schemaVersion == 1 && document.dataScope == nil) else {
            throw BackupError.unsupportedScope
        }
        let count = document.goals.count + document.tasks.count + document.timingSessions.count
        guard count <= maximumRecords else { throw BackupError.invalidContent("目标、任务和计时合计不能超过 50,000 条。") }
        guard allowEmpty || count > 0 else { throw BackupError.emptyDocument }
        func date(_ value: Date?) throws {
            if let value, !value.timeIntervalSince1970.isFinite { throw BackupError.invalidContent("日期无效。") }
        }
        func name(_ value: String) throws {
            guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw BackupError.invalidContent("名称不能为空。")
            }
        }
        try date(document.exportedAt)
        let goalIDs = Set(document.goals.map(\.id))
        let taskIDs = Set(document.tasks.map(\.id))
        let sessionIDs = Set(document.timingSessions.map(\.id))
        guard goalIDs.count == document.goals.count, taskIDs.count == document.tasks.count,
              sessionIDs.count == document.timingSessions.count else {
            throw BackupError.invalidContent("记录 ID 重复。")
        }
        for goal in document.goals {
            try name(goal.name); try date(goal.createdAt); try date(goal.deletedAt)
        }
        for task in document.tasks {
            try name(task.title); try date(task.createdAt); try date(task.completedAt); try date(task.deletedAt)
            if let goalID = task.goalID, !goalIDs.contains(goalID) {
                throw BackupError.invalidContent("任务引用了备份中不存在的目标。")
            }
        }
        guard document.timingSessions.filter({ $0.state != .finished }).count <= 1 else {
            throw BackupError.invalidContent("存在多段未结束计时，请先在原设备处理。")
        }
        var intervalCount = 0
        for session in document.timingSessions {
            try name(session.taskTitleSnapshot)
            try date(session.startedAt); try date(session.endedAt); try date(session.runningStartedAt)
            guard session.accumulatedSeconds.isFinite, session.accumulatedSeconds >= 0 else {
                throw BackupError.invalidContent("计时总时长无效。")
            }
            intervalCount += session.activeIntervals.count
            guard intervalCount <= 200_000 else { throw BackupError.invalidContent("有效计时区间不能超过 200,000 段。") }
            var previousEnd = session.startedAt
            for interval in session.activeIntervals {
                try date(interval.startedAt); try date(interval.endedAt)
                guard interval.endedAt >= interval.startedAt, interval.startedAt >= previousEnd else {
                    throw BackupError.invalidContent("计时区间倒置、重叠或顺序错误。")
                }
                previousEnd = interval.endedAt
            }
            let sum = session.activeIntervals.reduce(0) { $0 + $1.duration }
            // v1 encoded whole-second dates but retained fractional accumulatedSeconds.
            let tolerance = document.schemaVersion == 1 ? Double(session.activeIntervals.count) * 2 + 0.001 : 0.001
            guard sum.isFinite, abs(sum - session.accumulatedSeconds) <= tolerance else {
                throw BackupError.invalidContent("计时总时长与有效区间不一致。")
            }
            switch session.state {
            case .finished:
                guard let end = session.endedAt, end >= previousEnd, session.runningStartedAt == nil else {
                    throw BackupError.invalidContent("已结束计时的状态或结束时间无效。")
                }
            case .paused:
                guard session.endedAt == nil, session.runningStartedAt == nil else {
                    throw BackupError.invalidContent("暂停计时仍含运行起点或结束时间。")
                }
            case .running:
                guard session.endedAt == nil, let start = session.runningStartedAt, start >= previousEnd else {
                    throw BackupError.invalidContent("运行计时缺少有效起点。")
                }
            }
            // Historical snapshots may outlive the referenced task/goal; do not discard those sessions.
        }
    }

    private static func verify(document: ZhouJiBackupDocument, in context: ModelContext) throws {
        var goalsByID: [UUID: Goal] = [:]
        for goal in try context.fetch(FetchDescriptor<Goal>()) { goalsByID[goal.id] = goal }
        var tasksByID: [UUID: TodoTask] = [:]
        for task in try context.fetch(FetchDescriptor<TodoTask>()) { tasksByID[task.id] = task }
        var sessionsByID: [UUID: TimingSession] = [:]
        for session in try context.fetch(FetchDescriptor<TimingSession>()) { sessionsByID[session.id] = session }

        for dto in document.goals {
            guard let model = goalsByID[dto.id], BackupGoal(model) == dto else {
                throw BackupError.importFailed("目标字段校验失败。")
            }
        }
        for dto in document.tasks {
            guard let model = tasksByID[dto.id], BackupTask(model) == dto else {
                throw BackupError.importFailed("任务字段校验失败。")
            }
        }
        for dto in document.timingSessions {
            guard let model = sessionsByID[dto.id], BackupTimingSession(model) == dto else {
                throw BackupError.importFailed("计时字段校验失败。")
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
    var timingSessions: [BackupTimingSession]
    var dataScope: String? = nil
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
    var id: UUID
    var taskID: UUID
    var taskTitleSnapshot: String
    var goalIDSnapshot: UUID?
    var goalNameSnapshot: String?
    var startedAt: Date
    var endedAt: Date?
    var activeIntervals: [TimingInterval]
    var accumulatedSeconds: TimeInterval
    var runningStartedAt: Date?
    var state: TimingSessionState

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
