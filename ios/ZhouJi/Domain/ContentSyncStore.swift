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

}

enum ContentSyncError: LocalizedError {
    case disabled
    case server(String)
    case conflictCount(Int)

    var errorDescription: String? {
        switch self {
        case .disabled: "云同步尚未开放。"
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
    private(set) var pendingCount = 0
    private(set) var localOnlyCount = 0
    private(set) var conflicts: [SyncJournalConflict] = []
    private(set) var needsFullReconcile = false

    private let api: any ContentSyncServing
    private let forcesEnabled: Bool?
    private let journalDirectory: URL

    init(api: any ContentSyncServing = ContentSyncAPI(), forcesEnabled: Bool? = nil,
         journalDirectory: URL = URL.applicationSupportDirectory.appendingPathComponent("ContentSync")) {
        self.api = api
        self.forcesEnabled = forcesEnabled
        self.journalDirectory = journalDirectory
    }

    var isEnabled: Bool { forcesEnabled ?? ContentSyncFlag.isEnabled }

    private func journalStore(for scope: String) -> SyncJournalStore {
        SyncJournalStore(directory: journalDirectory, scope: scope)
    }

    func reloadJournal(scope: String) {
        do {
            let journal = try journalStore(for: scope).load()
            conflicts = journal.conflicts
            needsFullReconcile = journal.needsFullReconcile
            localOnlyCount = journal.entries.values.filter { $0.localOnlyCopy == true }.count
        } catch { message = error.localizedDescription }

    }

    /// Incremental changes not yet confirmed by the server.
    static func pendingChanges(in context: ModelContext, journal: SyncJournal) throws -> [SyncChangePayload] {
        let all = try factChanges(in: context)
        return all.filter { change in
            guard let entry = journal.entries[change.entityType + "/" + change.entityId] else { return true }
            if entry.cloudTombstone == true { return false }
            if let confirmedOp = entry.op, let confirmedPayload = entry.payload {
                return change.op != confirmedOp || !payloadsAreEquivalent(change.payload, confirmedPayload)
            }
            // A legacy journal cannot prove that mutable content is unchanged. Recheck it once,
            // then the applied response records a snapshot and subsequent scans stay quiet.
            return true
        }.map { change in
            let key = change.entityType + "/" + change.entityId
            let nextVersion = (journal.entries[key]?.version ?? 0) + 1
            return SyncChangePayload(
                clientOpId: change.clientOpId,
                entityType: change.entityType,
                entityId: change.entityId,
                op: change.op,
                version: nextVersion,
                updatedAt: change.updatedAt,
                payload: change.payload
            )
        }
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

    func uploadLibrary(context: ModelContext, token: String, scope: String, batchSize: Int = 100) async throws -> Int {
        try await sendChanges(context: context, token: token, scope: scope, batchSize: batchSize, fullUpload: true)
    }

    func pushPending(context: ModelContext, token: String, scope: String, batchSize: Int = 100) async throws -> Int {
        try await sendChanges(context: context, token: token, scope: scope, batchSize: batchSize, fullUpload: false)
    }

    private func sendChanges(context: ModelContext, token: String, scope: String, batchSize: Int, fullUpload: Bool) async throws -> Int {
        guard isEnabled else { throw ContentSyncError.disabled }
        guard !isBusy else { return 0 }
        isBusy = true
        defer {
            isBusy = false
            progress = nil
        }
        guard (1...200).contains(batchSize) else { throw ContentSyncError.server("同步批次大小无效。") }
        let phase = fullUpload ? "正在上传" : "正在同步"
        let store = journalStore(for: scope)
        do {
            var journal = try store.load()
            let changes = try Self.pendingChanges(in: context, journal: journal)
            if !fullUpload, changes.count > SyncJournal.maxPending {
                journal.needsFullReconcile = true
                try store.save(journal)
                needsFullReconcile = true
                pendingCount = changes.count
                throw ContentSyncError.server("待同步项过多，需要完整对账")
            }
            progress = ContentSyncProgress(phase: phase, completed: 0, total: changes.count)
            var index = 0
            while index < changes.count {
                let end = min(index + batchSize, changes.count)
                let slice = Array(changes[index..<end])
                let response = try await api.push(token: token, changes: slice)
                let byOpId = Dictionary(uniqueKeysWithValues: slice.map { ($0.clientOpId, $0) })
                for item in response.applied {
                    if let change = byOpId[item.clientOpId] {
                        journal.noteApplied(
                            entityType: change.entityType,
                            entityId: change.entityId,
                            version: item.version,
                            updatedAt: change.updatedAt,
                            op: change.op,
                            payload: change.payload
                        )
                    }
                }
                for conflict in response.conflicts {
                    journal.noteConflict(SyncJournalConflict(
                        entityType: conflict.entityType,
                        entityId: conflict.entityId,
                        serverVersion: conflict.serverVersion,
                        serverUpdatedAt: conflict.serverUpdatedAt,
                        serverDeletedAt: conflict.serverDeletedAt,
                        serverPayload: conflict.serverPayload,
                        localChange: byOpId[conflict.clientOpId]
                    ))
                }
                index = end
                progress = ContentSyncProgress(phase: phase, completed: index, total: changes.count)
            }
            if fullUpload { journal.needsFullReconcile = false }
            try store.save(journal)
            conflicts = journal.conflicts
            needsFullReconcile = journal.needsFullReconcile
            localOnlyCount = journal.entries.values.filter { $0.localOnlyCopy == true }.count
            pendingCount = try Self.pendingChanges(in: context, journal: journal).count
            if !journal.conflicts.isEmpty {
                message = ContentSyncError.conflictCount(journal.conflicts.count).localizedDescription
            } else {
                var summary = fullUpload ? "已上传 \(changes.count) 条记录" : "已同步 \(changes.count) 项变更"
                if pendingCount > 0 { summary += "；仍有 \(pendingCount) 项新变更待同步" }
                if localOnlyCount > 0 { summary += "；另有 \(localOnlyCount) 项副本仅存于本机，不再上传" }
                message = summary + "。"
            }
            return changes.count
        } catch {
            message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            throw error
        }
    }

    /// R1: user picks local or cloud for one conflict.
    func resolveConflict(
        _ conflict: SyncJournalConflict,
        keepLocal: Bool,
        context: ModelContext,
        token: String,
        scope: String
    ) async {
        guard isEnabled, !isBusy else { return }
        isBusy = true
        defer { isBusy = false }
        let store = journalStore(for: scope)
        do {
            var journal = try store.load()
            let isPurgedCloudEntity = conflict.serverDeletedAt != nil && conflict.serverPayload.isEmpty
            if keepLocal && isPurgedCloudEntity {
                journal.noteApplied(
                    entityType: conflict.entityType,
                    entityId: conflict.entityId,
                    version: conflict.serverVersion,
                    updatedAt: conflict.serverUpdatedAt,
                    op: "delete",
                    payload: [:],
                    cloudTombstone: true,
                    localOnlyCopy: true
                )
                message = "云端记录已永久删除；保留的副本仅存于本机，不再上传。"
            } else if keepLocal {
                guard var local = conflict.localChange else {
                    message = "本机版本不可用，请从云端恢复。"
                    return
                }
                local = SyncChangePayload(
                    clientOpId: UUID().uuidString,
                    entityType: local.entityType,
                    entityId: local.entityId,
                    op: local.op,
                    version: conflict.serverVersion + 1,
                    updatedAt: max(local.updatedAt, conflict.serverUpdatedAt + 1),
                    payload: local.payload
                )
                let response = try await api.push(token: token, changes: [local])
                if let item = response.applied.first {
                    journal.noteApplied(
                        entityType: local.entityType,
                        entityId: local.entityId,
                        version: item.version,
                        updatedAt: local.updatedAt,
                        op: local.op,
                        payload: local.payload
                    )
                    message = "已保留本机版本。"
                } else if let next = response.conflicts.first {
                    journal.noteConflict(SyncJournalConflict(
                        entityType: next.entityType,
                        entityId: next.entityId,
                        serverVersion: next.serverVersion,
                        serverUpdatedAt: next.serverUpdatedAt,
                        serverDeletedAt: next.serverDeletedAt,
                        serverPayload: next.serverPayload,
                        localChange: local
                    ))
                    message = "云端仍有更新，请重试或选择云端版本。"
                }
            } else {
                try Self.apply(
                    entities: [SyncEntityPayload(
                        entityType: conflict.entityType,
                        entityId: conflict.entityId,
                        version: conflict.serverVersion,
                        serverSeq: 0,
                        updatedAt: conflict.serverUpdatedAt,
                        deletedAt: conflict.serverDeletedAt,
                        payload: conflict.serverPayload
                    )],
                    in: context
                )
                journal.noteApplied(
                    entityType: conflict.entityType,
                    entityId: conflict.entityId,
                    version: conflict.serverVersion,
                    updatedAt: conflict.serverUpdatedAt,
                    op: conflict.serverDeletedAt == nil ? "upsert" : "delete",
                    payload: conflict.serverPayload,
                    cloudTombstone: isPurgedCloudEntity
                )
                message = isPurgedCloudEntity ? "已接受云端删除记录。" : "已使用云端版本。"
            }
            try store.save(journal)
            conflicts = journal.conflicts
            localOnlyCount = journal.entries.values.filter { $0.localOnlyCopy == true }.count
        } catch {
            message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
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
        let store = journalStore(for: scope)
        do {
            var journal = try store.load()
            var cursor = 0
            var applied = 0
            progress = ContentSyncProgress(phase: "正在恢复", completed: 0, total: 0)
            while true {
                let page = try await api.pull(token: token, cursor: cursor, limit: batchSize)
                try Self.apply(entities: page.entities, in: context)
                for entity in page.entities {
                    journal.noteApplied(
                        entityType: entity.entityType,
                        entityId: entity.entityId,
                        version: entity.version,
                        updatedAt: entity.updatedAt,
                        op: entity.deletedAt == nil ? "upsert" : "delete",
                        payload: entity.payload,
                        cloudTombstone: entity.deletedAt != nil && entity.payload.isEmpty
                    )
                }
                applied += page.entities.count
                cursor = page.cursor
                progress = ContentSyncProgress(phase: "正在恢复", completed: applied, total: applied)
                if !page.hasMore { break }
            }
            try store.save(journal)
            conflicts = journal.conflicts
            localOnlyCount = journal.entries.values.filter { $0.localOnlyCopy == true }.count
            if localOnlyCount > 0 {
                message = "已从云端恢复 \(applied) 条记录；另有 \(localOnlyCount) 项副本仅存于本机，不再上传。"
            } else {
                message = "已从此账户云端恢复 \(applied) 条记录。未删除本机多出的记录。"
            }
            return applied
        } catch {
            message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            throw error
        }
    }

    // MARK: - Mapping

    private static func payloadsAreEquivalent(
        _ lhs: [String: SyncJSONValue],
        _ rhs: [String: SyncJSONValue]
    ) -> Bool {
        guard lhs.count == rhs.count else { return false }
        return lhs.allSatisfy { key, value in
            guard let other = rhs[key] else { return false }
            return jsonValuesAreEquivalent(value, other)
        }
    }

    private static func jsonValuesAreEquivalent(_ lhs: SyncJSONValue, _ rhs: SyncJSONValue) -> Bool {
        switch (lhs, rhs) {
        case (.int(let lhs), .double(let rhs)):
            return Double(lhs) == rhs
        case (.double(let lhs), .int(let rhs)):
            return lhs == Double(rhs)
        case (.array(let lhs), .array(let rhs)):
            return lhs.count == rhs.count && zip(lhs, rhs).allSatisfy {
                jsonValuesAreEquivalent($0.0, $0.1)
            }
        case (.object(let lhs), .object(let rhs)):
            return payloadsAreEquivalent(lhs, rhs)
        default:
            return lhs == rhs
        }
    }

    static func factChanges(in context: ModelContext) throws -> [SyncChangePayload] {
        let goals = try context.fetch(FetchDescriptor<Goal>())
        let tasks = try context.fetch(FetchDescriptor<TodoTask>())
        let allSessions = try context.fetch(FetchDescriptor<TimingSession>())
        for session in allSessions { _ = try session.activeIntervals }
        let sessions = allSessions.filter { $0.state == .finished }
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
            let intervals = SyncJSONValue.array(try session.activeIntervals.map {
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

    private static func validateCloudEntities(_ entities: [SyncEntityPayload]) throws {
        func invalid() -> ContentSyncError { .server("云端记录不完整或格式错误，本批数据未写入本机。") }
        func date(_ payload: [String: SyncJSONValue], _ key: String, optional: Bool = false) throws -> Int? {
            if optional, case .null? = payload[key] { return nil }
            guard case .int(let value)? = payload[key] else { throw invalid() }
            return value
        }
        func identifier(_ payload: [String: SyncJSONValue], _ key: String, optional: Bool = false) throws {
            if optional, case .null? = payload[key] { return }
            guard case .string(let value)? = payload[key], UUID(uuidString: value) != nil else { throw invalid() }
        }
        func text(_ payload: [String: SyncJSONValue], _ key: String) throws {
            guard case .string(let value)? = payload[key], !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw invalid() }
        }
        var identifiers = Set<String>()
        for entity in entities {
            guard UUID(uuidString: entity.entityId) != nil,
                  identifiers.insert(entity.entityType + "/" + entity.entityId).inserted else { throw invalid() }
            if entity.deletedAt != nil, entity.payload.isEmpty {
                guard entity.entityType == "goal" || entity.entityType == "task" else { throw invalid() }
                continue
            }
            let payload = entity.payload
            switch entity.entityType {
            case "goal":
                try text(payload, "name")
                _ = try date(payload, "createdAt")
                _ = try date(payload, "deletedAt", optional: true)
            case "task":
                try text(payload, "title")
                _ = try date(payload, "createdAt")
                _ = try date(payload, "completedAt", optional: true)
                _ = try date(payload, "deletedAt", optional: true)
                try identifier(payload, "goalId", optional: true)
            case "timing_session":
                try identifier(payload, "taskId")
                try identifier(payload, "goalIdSnapshot", optional: true)
                try text(payload, "taskTitleSnapshot")
                switch payload["goalNameSnapshot"] {
                case nil, .null?, .string?: break
                default: throw invalid()
                }
                guard let start = try date(payload, "startedAt"), let end = try date(payload, "endedAt"), end >= start,
                      case .array(let intervals)? = payload["activeIntervals"] else { throw invalid() }
                let accumulated: Double
                switch payload["accumulatedSeconds"] {
                case .double(let value)?: accumulated = value
                case .int(let value)?: accumulated = Double(value)
                default: throw invalid()
                }
                guard accumulated.isFinite, accumulated >= 0 else { throw invalid() }
                var total: Double = 0
                var previousEnd = start
                for interval in intervals {
                    guard case .object(let values) = interval,
                          let intervalStart = try date(values, "startedAt"),
                          let intervalEnd = try date(values, "endedAt"),
                          intervalStart >= previousEnd, intervalEnd >= intervalStart, intervalEnd <= end else { throw invalid() }
                    total += Double(intervalEnd) - Double(intervalStart)
                    previousEnd = intervalEnd
                }
                // The existing protocol rounds dates to seconds; preserve its interval precision tolerance.
                guard abs(total - accumulated) <= Double(intervals.count) * 2 + 0.001 else { throw invalid() }
            default: throw invalid()
            }
        }
    }

    static func apply(entities: [SyncEntityPayload], in context: ModelContext) throws {
        try validateCloudEntities(entities)
        try context.save()
        do {
            var goalsByID: [UUID: Goal] = [:]
            for goal in try context.fetch(FetchDescriptor<Goal>()) { goalsByID[goal.id] = goal }
            var tasksByID: [UUID: TodoTask] = [:]
            for task in try context.fetch(FetchDescriptor<TodoTask>()) { tasksByID[task.id] = task }
            var sessionsByID: [UUID: TimingSession] = [:]
            for session in try context.fetch(FetchDescriptor<TimingSession>()) { sessionsByID[session.id] = session }

            func requiredDate(_ value: SyncJSONValue?) throws -> Date {
                guard let date = dateString(value) else { throw ContentSyncError.server("云端日期格式无效，本批数据未写入本机。") }
                return date
            }

            func dateString(_ value: SyncJSONValue?) -> Date? {
                guard case .int(let seconds)? = value else { return nil }
                return Date(timeIntervalSince1970: TimeInterval(seconds))
            }

            for entity in entities where entity.entityType == "goal" {
                guard let id = UUID(uuidString: entity.entityId) else { continue }
                if let deletedAt = entity.deletedAt, entity.payload.isEmpty {
                    guard let model = goalsByID[id] else { continue }
                    model.deletedAt = Date(timeIntervalSince1970: TimeInterval(deletedAt))
                    for task in tasksByID.values where task.goal?.id == id {
                        task.goal = nil
                    }
                    continue
                }
                let name: String = {
                    if case .string(let value) = entity.payload["name"] { return value }
                    return ""
                }()
                var iconName: String?
                if case .string(let value) = entity.payload["iconName"] { iconName = value }
                let createdAt = try requiredDate(entity.payload["createdAt"])
                let deletedAt = dateString(entity.payload["deletedAt"])
                let model = goalsByID[id] ?? Goal(id: id, name: name, iconName: iconName, createdAt: createdAt)
                if !name.isEmpty { model.name = name }
                if let iconName { model.iconName = iconName }
                model.createdAt = createdAt
                model.deletedAt = deletedAt
                if goalsByID[id] == nil { context.insert(model) }
                goalsByID[id] = model
            }

            for entity in entities where entity.entityType == "task" {
                guard let id = UUID(uuidString: entity.entityId) else { continue }
                if let deletedAt = entity.deletedAt, entity.payload.isEmpty {
                    guard let model = tasksByID[id] else { continue }
                    model.deletedAt = Date(timeIntervalSince1970: TimeInterval(deletedAt))
                    continue
                }
                let title: String = {
                    if case .string(let value) = entity.payload["title"] { return value }
                    return ""
                }()
                let createdAt = try requiredDate(entity.payload["createdAt"])
                let completedAt = dateString(entity.payload["completedAt"])
                let deletedAt = dateString(entity.payload["deletedAt"])
                let model = tasksByID[id] ?? TodoTask(id: id, title: title, createdAt: createdAt)
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
                let startedAt = try requiredDate(entity.payload["startedAt"])
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
                    try model.setActiveIntervals(intervals)
                    model.accumulatedSeconds = accumulated
                    model.state = .finished
                } else {
                    let model = try TimingSession(
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
        } catch { context.rollback(); throw error }
    }
}
