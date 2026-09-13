import Foundation
import Observation
import SwiftData

/// Content sync stays off until product release. Debug/UI tests opt in via launch argument.
enum ContentSyncFlag {
    static let defaultsKey = "contentSync.enabled"

    static var isEnabled: Bool {
        if ProcessInfo.processInfo.arguments.contains("-ZJSyncContent") { return true }
        return UserDefaults.standard.bool(forKey: defaultsKey)
    }

    static func setEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: defaultsKey)
    }
}

enum ContentSyncError: LocalizedError {
    case disabled
    case requiresAccount
    case requiresAccountLibrary
    case server(String)
    case conflictCount(Int)

    var errorDescription: String? {
        switch self {
        case .disabled: "云同步尚未开放。"
        case .requiresAccount: "请先登录账户后再使用同步。"
        case .requiresAccountLibrary: "请先打开此账户的本机记录，再执行同步。"
        case .server(let message): message
        case .conflictCount(let count): "有 \(count) 条记录在云端更新，可稍后选择保留本机或使用云端。"
        }
    }
}

struct ContentSyncProgress: Equatable {
    var phase: String
    var completed: Int
    var total: Int
}

@MainActor @Observable
final class ContentSyncStore {
    private(set) var isBusy = false
    private(set) var progress: ContentSyncProgress?
    private(set) var message: String?
    private(set) var latestSeq = 0
    private(set) var softDeletedCount = 0

    private let api: any ContentSyncServing
    private let defaults: UserDefaults
    private let scopeKeyPrefix = "contentSync.cursor."
    private let forcesEnabled: Bool?

    init(api: any ContentSyncServing = ContentSyncAPI(), defaults: UserDefaults = .standard,
         forcesEnabled: Bool? = nil) {
        self.api = api
        self.defaults = defaults
        self.forcesEnabled = forcesEnabled
    }

    var isEnabled: Bool { forcesEnabled ?? ContentSyncFlag.isEnabled }

    func cursor(for scope: String) -> Int { defaults.integer(forKey: scopeKeyPrefix + scope) }

    private func setCursor(_ value: Int, for scope: String) {
        defaults.set(value, forKey: scopeKeyPrefix + scope)
    }

    func refreshStatus(token: String) async {
        guard isEnabled else { return }
        do {
            let status = try await api.status(token: token)
            latestSeq = status.latestSeq
            softDeletedCount = status.softDeletedCount
        } catch {
            message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    func uploadLibrary(context: ModelContext, token: String, batchSize: Int = 100) async throws -> Int {
        guard isEnabled else { throw ContentSyncError.disabled }
        guard !isBusy else { return 0 }
        isBusy = true
        defer {
            isBusy = false
            progress = nil
        }
        do {
            let changes = try Self.factChanges(in: context)
            progress = ContentSyncProgress(phase: "正在上传", completed: 0, total: changes.count)
            var conflicts = 0
            var index = 0
            while index < changes.count {
                let end = min(index + batchSize, changes.count)
                let response = try await api.push(token: token, changes: Array(changes[index..<end]))
                conflicts += response.conflicts.count
                index = end
                progress = ContentSyncProgress(phase: "正在上传", completed: index, total: changes.count)
            }
            message = conflicts > 0
                ? ContentSyncError.conflictCount(conflicts).localizedDescription
                : "已上传 \(changes.count) 条记录到此账户。本机记录未删除。"
            return changes.count
        } catch {
            message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            throw error
        }
    }

    func restoreIntoLibrary(context: ModelContext, token: String, scope: String, batchSize: Int = 100) async throws -> Int {
        guard isEnabled else { throw ContentSyncError.disabled }
        guard !isBusy else { return 0 }
        isBusy = true
        defer {
            isBusy = false
            progress = nil
        }
        do {
            var cursor = 0
            var applied = 0
            progress = ContentSyncProgress(phase: "正在恢复", completed: 0, total: 0)
            while true {
                let page = try await api.pull(token: token, cursor: cursor, limit: batchSize)
                try Self.apply(entities: page.entities, in: context)
                applied += page.entities.count
                cursor = page.cursor
                setCursor(cursor, for: scope)
                progress = ContentSyncProgress(phase: "正在恢复", completed: applied, total: applied)
                if !page.hasMore { break }
            }
            message = "已从此账户云端恢复 \(applied) 条记录。未删除本机多出的记录。"
            return applied
        } catch {
            message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            throw error
        }
    }

    // MARK: - Mapping

    static func factChanges(in context: ModelContext) throws -> [SyncChangePayload] {
        let goals = try context.fetch(FetchDescriptor<Goal>())
        let tasks = try context.fetch(FetchDescriptor<TodoTask>())
        let sessions = try context.fetch(FetchDescriptor<TimingSession>()).filter { $0.state == .finished }
        var changes: [SyncChangePayload] = []

        func ts(_ date: Date?) -> SyncJSONValue {
            guard let date else { return .null }
            return .int(Int(date.timeIntervalSince1970))
        }

        for goal in goals {
            changes.append(SyncChangePayload(
                clientOpId: UUID().uuidString,
                entityType: "goal",
                entityId: goal.id.uuidString,
                op: goal.deletedAt == nil ? "upsert" : "delete",
                version: 1,
                updatedAt: Int((goal.deletedAt ?? goal.createdAt).timeIntervalSince1970),
                payload: [
                    "name": .string(goal.name),
                    "iconName": goal.iconName.map(SyncJSONValue.string) ?? .null,
                    "createdAt": ts(goal.createdAt),
                    "deletedAt": ts(goal.deletedAt)
                ]
            ))
        }
        for task in tasks {
            changes.append(SyncChangePayload(
                clientOpId: UUID().uuidString,
                entityType: "task",
                entityId: task.id.uuidString,
                op: task.deletedAt == nil ? "upsert" : "delete",
                version: 1,
                updatedAt: Int((task.deletedAt ?? task.completedAt ?? task.createdAt).timeIntervalSince1970),
                payload: [
                    "title": .string(task.title),
                    "createdAt": ts(task.createdAt),
                    "completedAt": ts(task.completedAt),
                    "deletedAt": ts(task.deletedAt),
                    "goalId": task.goal.map { SyncJSONValue.string($0.id.uuidString) } ?? .null
                ]
            ))
        }
        for session in sessions {
            let intervals = SyncJSONValue.array(session.activeIntervals.map {
                .object(["startedAt": ts($0.startedAt), "endedAt": ts($0.endedAt)])
            })
            changes.append(SyncChangePayload(
                clientOpId: UUID().uuidString,
                entityType: "timing_session",
                entityId: session.id.uuidString,
                op: "upsert",
                version: 1,
                updatedAt: Int((session.endedAt ?? session.startedAt).timeIntervalSince1970),
                payload: [
                    "taskId": .string(session.taskID.uuidString),
                    "taskTitleSnapshot": .string(session.taskTitleSnapshot),
                    "goalIdSnapshot": session.goalIDSnapshot.map { SyncJSONValue.string($0.uuidString) } ?? .null,
                    "goalNameSnapshot": session.goalNameSnapshot.map(SyncJSONValue.string) ?? .null,
                    "startedAt": ts(session.startedAt),
                    "endedAt": ts(session.endedAt),
                    "accumulatedSeconds": .double(session.accumulatedSeconds),
                    "activeIntervals": intervals
                ]
            ))
        }
        return changes
    }

    static func apply(entities: [SyncEntityPayload], in context: ModelContext) throws {
        var goalsByID: [UUID: Goal] = [:]
        for goal in try context.fetch(FetchDescriptor<Goal>()) { goalsByID[goal.id] = goal }
        var tasksByID: [UUID: TodoTask] = [:]
        for task in try context.fetch(FetchDescriptor<TodoTask>()) { tasksByID[task.id] = task }
        var sessionsByID: [UUID: TimingSession] = [:]
        for session in try context.fetch(FetchDescriptor<TimingSession>()) { sessionsByID[session.id] = session }

        func dateString(_ value: SyncJSONValue?) -> Date? {
            guard case .int(let seconds)? = value else { return nil }
            return Date(timeIntervalSince1970: TimeInterval(seconds))
        }

        for entity in entities where entity.entityType == "goal" {
            guard let id = UUID(uuidString: entity.entityId) else { continue }
            let name: String = {
                if case .string(let value) = entity.payload["name"] { return value }
                return ""
            }()
            var iconName: String?
            if case .string(let value) = entity.payload["iconName"] { iconName = value }
            let createdAt = dateString(entity.payload["createdAt"]) ?? .now
            let deletedAt = dateString(entity.payload["deletedAt"])
            let model = goalsByID[id] ?? Goal(id: id, name: name.isEmpty ? "目标" : name, iconName: iconName, createdAt: createdAt)
            if !name.isEmpty { model.name = name }
            if let iconName { model.iconName = iconName }
            model.createdAt = createdAt
            model.deletedAt = deletedAt
            if goalsByID[id] == nil { context.insert(model) }
            goalsByID[id] = model
        }

        for entity in entities where entity.entityType == "task" {
            guard let id = UUID(uuidString: entity.entityId) else { continue }
            let title: String = {
                if case .string(let value) = entity.payload["title"] { return value }
                return ""
            }()
            let createdAt = dateString(entity.payload["createdAt"]) ?? .now
            let completedAt = dateString(entity.payload["completedAt"])
            let deletedAt = dateString(entity.payload["deletedAt"])
            let model = tasksByID[id] ?? TodoTask(id: id, title: title.isEmpty ? "任务" : title, createdAt: createdAt)
            if !title.isEmpty { model.title = title }
            model.createdAt = createdAt
            model.completedAt = completedAt
            model.deletedAt = deletedAt
            if case .string(let goalIdString) = entity.payload["goalId"], let goalId = UUID(uuidString: goalIdString) {
                model.goal = goalsByID[goalId]
            } else {
                model.goal = nil
            }
            if tasksByID[id] == nil { context.insert(model) }
            tasksByID[id] = model
        }

        for entity in entities where entity.entityType == "timing_session" {
            guard let id = UUID(uuidString: entity.entityId),
                  case .string(let taskIDString)? = entity.payload["taskId"],
                  let taskID = UUID(uuidString: taskIDString) else { continue }
            var snapshot = ""
            if case .string(let value) = entity.payload["taskTitleSnapshot"] { snapshot = value }
            var goalID: UUID?
            if case .string(let value) = entity.payload["goalIdSnapshot"] { goalID = UUID(uuidString: value) }
            var goalName: String?
            if case .string(let value) = entity.payload["goalNameSnapshot"] { goalName = value }
            let startedAt = dateString(entity.payload["startedAt"]) ?? .now
            let endedAt = dateString(entity.payload["endedAt"])
            var accumulated: Double = 0
            if case .double(let value) = entity.payload["accumulatedSeconds"] { accumulated = value }
            else if case .int(let value) = entity.payload["accumulatedSeconds"] { accumulated = Double(value) }
            var intervals: [TimingInterval] = []
            if case .array(let items) = entity.payload["activeIntervals"] {
                intervals = items.compactMap { item in
                    guard case .object(let map) = item,
                          let start = dateString(map["startedAt"]),
                          let end = dateString(map["endedAt"]) else { return nil }
                    return TimingInterval(startedAt: start, endedAt: end)
                }
            }
            if let model = sessionsByID[id] {
                model.taskID = taskID
                model.taskTitleSnapshot = snapshot
                model.goalIDSnapshot = goalID
                model.goalNameSnapshot = goalName
                model.startedAt = startedAt
                model.endedAt = endedAt
                model.activeIntervals = intervals
                model.accumulatedSeconds = accumulated
                model.state = .finished
            } else {
                let model = TimingSession(
                    id: id,
                    taskID: taskID,
                    taskTitleSnapshot: snapshot,
                    goalIDSnapshot: goalID,
                    goalNameSnapshot: goalName,
                    startedAt: startedAt,
                    endedAt: endedAt,
                    activeIntervals: intervals,
                    accumulatedSeconds: accumulated,
                    state: .finished
                )
                context.insert(model)
                sessionsByID[id] = model
            }
        }

        try context.save()
    }
}
