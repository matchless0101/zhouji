import Foundation
import SwiftData
import Testing
@testable import ZhouJi

@MainActor private final class SyncAPIMock: ContentSyncServing, @unchecked Sendable {
    var pushed: [[SyncChangePayload]] = []
    var pullPages: [SyncPullResponse] = []
    var status = SyncStatusResponse(accountId: "a1", latestSeq: 0, softDeletedCount: 0, syncEnabled: true)
    var onPush: (() throws -> Void)?

    func push(token: String, changes: [SyncChangePayload]) async throws -> SyncPushResponse {
        pushed.append(changes)
        try onPush?()
        onPush = nil
        let applied = changes.enumerated().map { index, change in
            SyncAppliedItem(
                clientOpId: change.clientOpId,
                entityType: change.entityType,
                entityId: change.entityId,
                version: change.version,
                serverSeq: index + 1,
                deduped: false
            )
        }
        return SyncPushResponse(applied: applied, conflicts: [], serverTime: Int(Date.now.timeIntervalSince1970))
    }

    func pull(token: String, cursor: Int, limit: Int) async throws -> SyncPullResponse {
        if pullPages.isEmpty {
            return SyncPullResponse(entities: [], cursor: cursor, hasMore: false)
        }
        return pullPages.removeFirst()
    }

    func status(token: String) async throws -> SyncStatusResponse { status }
}

@MainActor
struct ContentSyncStoreTests {
    @Test func factChangesSkipUnfinishedSessionsAndIncludeSoftDeletes() throws {
        let context = try makeContext()
        let goal = try GoalService.create(name: "论文", in: context)
        let task = try TaskService.create(title: "写摘要", goal: goal, in: context)
        try TaskService.softDelete(task, in: context)
        let start = Date.now.addingTimeInterval(-600)
        let finished = TimingSession(
            taskID: task.id,
            taskTitleSnapshot: task.title,
            startedAt: start,
            endedAt: start.addingTimeInterval(600),
            activeIntervals: [TimingInterval(startedAt: start, endedAt: start.addingTimeInterval(600))],
            accumulatedSeconds: 600,
            state: .finished
        )
        let running = TimingSession(
            taskID: task.id,
            taskTitleSnapshot: task.title,
            startedAt: start,
            runningStartedAt: start,
            state: .running
        )
        context.insert(finished)
        context.insert(running)
        try context.save()

        let changes = try ContentSyncStore.factChanges(in: context)
        let types = Set(changes.map(\.entityType))
        #expect(types == ["goal", "task", "timing_session"])
        #expect(changes.filter { $0.entityType == "timing_session" }.count == 1)
        let taskChange = try #require(changes.first { $0.entityType == "task" })
        #expect(taskChange.op == "delete")
    }

    @Test func applyRestoresGoalsTasksAndFinishedSessions() throws {
        let context = try makeContext()
        let goalId = UUID()
        let taskId = UUID()
        let sessionId = UUID()
        let entities: [SyncEntityPayload] = [
            SyncEntityPayload(
                entityType: "goal",
                entityId: goalId.uuidString,
                version: 1,
                serverSeq: 1,
                updatedAt: 1_000,
                deletedAt: nil,
                payload: [
                    "name": .string("论文"),
                    "iconName": .string("book.closed"),
                    "createdAt": .int(1_000),
                    "deletedAt": .null
                ]
            ),
            SyncEntityPayload(
                entityType: "task",
                entityId: taskId.uuidString,
                version: 1,
                serverSeq: 2,
                updatedAt: 1_100,
                deletedAt: nil,
                payload: [
                    "title": .string("写摘要"),
                    "createdAt": .int(1_100),
                    "completedAt": .int(1_200),
                    "deletedAt": .null,
                    "goalId": .string(goalId.uuidString)
                ]
            ),
            SyncEntityPayload(
                entityType: "timing_session",
                entityId: sessionId.uuidString,
                version: 1,
                serverSeq: 3,
                updatedAt: 1_800,
                deletedAt: nil,
                payload: [
                    "taskId": .string(taskId.uuidString),
                    "taskTitleSnapshot": .string("写摘要"),
                    "goalIdSnapshot": .string(goalId.uuidString),
                    "goalNameSnapshot": .string("论文"),
                    "startedAt": .int(1_200),
                    "endedAt": .int(1_800),
                    "accumulatedSeconds": .double(600),
                    "activeIntervals": .array([.object(["startedAt": .int(1_200), "endedAt": .int(1_800)])])
                ]
            )
        ]
        try ContentSyncStore.apply(entities: entities, in: context)
        let tasks = try context.fetch(FetchDescriptor<TodoTask>())
        let sessions = try context.fetch(FetchDescriptor<TimingSession>())
        #expect(tasks.count == 1)
        #expect(tasks[0].title == "写摘要")
        #expect(tasks[0].goal?.id == goalId)
        #expect(sessions.count == 1)
        #expect(sessions[0].accumulatedSeconds == 600)
        #expect(sessions[0].state == .finished)
    }

    @Test func uploadAndRestoreRoundTripThroughMockAPI() async throws {
        let source = try makeContext()
        let task = try TaskService.create(title: "上传任务", in: source)
        try TaskService.setCompleted(task, completed: true, in: source)
        let start = Date.now.addingTimeInterval(-300)
        let session = TimingSession(
            taskID: task.id,
            taskTitleSnapshot: task.title,
            startedAt: start,
            endedAt: start.addingTimeInterval(300),
            activeIntervals: [TimingInterval(startedAt: start, endedAt: start.addingTimeInterval(300))],
            accumulatedSeconds: 300,
            state: .finished
        )
        source.insert(session)
        try source.save()

        let journalDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let api = SyncAPIMock()
        let store = ContentSyncStore(
            api: api,
            defaults: UserDefaults(suiteName: "content-sync-tests")!,
            forcesEnabled: true,
            journalDirectory: journalDir
        )
        let uploaded = try await store.uploadLibrary(context: source, token: "token", scope: "account-test")
        #expect(uploaded >= 2)
        #expect(!api.pushed.isEmpty)
        #expect(store.message?.contains("已上传") == true)
        #expect(store.pendingCount == 0)

        let changes = try ContentSyncStore.factChanges(in: source)
        let entities = changes.map { change in
            SyncEntityPayload(
                entityType: change.entityType,
                entityId: change.entityId,
                version: change.version,
                serverSeq: 1,
                updatedAt: change.updatedAt,
                deletedAt: change.op == "delete" ? change.updatedAt : nil,
                payload: change.payload
            )
        }
        api.pullPages = [SyncPullResponse(entities: entities, cursor: entities.count, hasMore: false)]
        let target = try makeContext()
        let restored = try await store.restoreIntoLibrary(context: target, token: "token", scope: "account-test")
        #expect(restored == entities.count)
        #expect(try target.fetch(FetchDescriptor<TodoTask>()).count == 1)
        #expect(try target.fetch(FetchDescriptor<TimingSession>()).count == 1)

        // Second upload should be empty pending after journal refresh.
        let second = try ContentSyncStore.pendingChanges(
            in: source,
            journal: SyncJournalStore(directory: journalDir, scope: "account-test").load()
        )
        #expect(second.isEmpty)
    }

    @Test func legacyJournalRequiresOneConservativeContentRecheck() throws {
        let context = try makeContext()
        let task = TodoTask(title: "旧日志任务", createdAt: Date(timeIntervalSince1970: 1_000))
        context.insert(task)
        try context.save()
        let journalDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: journalDir, withIntermediateDirectories: true)
        let scope = "legacy"
        let key = "task/\(task.id.uuidString)"
        let json = """
        {
          "cursor": 0,
          "entries": {
            "\(key)": { "version": 1, "updatedAt": 1000 }
          },
          "conflicts": [],
          "needsFullReconcile": false
        }
        """
        let fileURL = journalDir.appendingPathComponent("sync-journal-\(scope).json")
        try #require(json.data(using: .utf8)).write(to: fileURL)

        let journal = SyncJournalStore(directory: journalDir, scope: scope).load()
        #expect(journal.entries[key]?.version == 1)
        #expect(journal.entries[key]?.payload == nil)
        let pending = try ContentSyncStore.pendingChanges(in: context, journal: journal)
        let change = try #require(pending.first)
        #expect(change.entityId == task.id.uuidString)
        #expect(change.version == 2)

        var confirmedJournal = journal
        confirmedJournal.noteApplied(
            entityType: change.entityType,
            entityId: change.entityId,
            version: change.version,
            updatedAt: change.updatedAt,
            op: change.op,
            payload: change.payload
        )
        #expect(try ContentSyncStore.pendingChanges(in: context, journal: confirmedJournal).isEmpty)
    }

    @Test func pendingChangesDetectContentEditsWithoutRelyingOnTimestamps() async throws {
        let context = try makeContext()
        let createdAt = Date(timeIntervalSince1970: 1_000)
        let completedAt = Date(timeIntervalSince1970: 2_000)
        let goal = Goal(name: "旧目标", iconName: "target", createdAt: createdAt)
        let task = TodoTask(
            title: "旧任务",
            createdAt: createdAt,
            completedAt: completedAt,
            goal: goal
        )
        context.insert(goal)
        context.insert(task)
        try context.save()

        let journalDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let api = SyncAPIMock()
        let store = ContentSyncStore(
            api: api,
            defaults: UserDefaults(suiteName: "content-sync-tests")!,
            forcesEnabled: true,
            journalDirectory: journalDir
        )
        _ = try await store.pushPending(context: context, token: "t", scope: "content-edits")

        goal.name = "新目标"
        goal.iconName = "book.closed"
        task.title = "新任务"
        task.completedAt = nil
        try context.save()

        let pending = try ContentSyncStore.pendingChanges(
            in: context,
            journal: SyncJournalStore(directory: journalDir, scope: "content-edits").load()
        )
        let goalChange = try #require(pending.first { $0.entityId == goal.id.uuidString })
        let taskChange = try #require(pending.first { $0.entityId == task.id.uuidString })
        #expect(goalChange.payload["name"] == .string("新目标"))
        #expect(goalChange.payload["iconName"] == .string("book.closed"))
        #expect(taskChange.payload["title"] == .string("新任务"))
        #expect(taskChange.payload["completedAt"] == .null)
    }

    @Test func pendingChangesDetectUndoDeleteEvenWhenTimestampMovesBackward() async throws {
        let context = try makeContext()
        let task = TodoTask(title: "撤销删除", createdAt: Date(timeIntervalSince1970: 1_000))
        context.insert(task)
        try context.save()

        let journalDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let api = SyncAPIMock()
        let store = ContentSyncStore(
            api: api,
            defaults: UserDefaults(suiteName: "content-sync-tests")!,
            forcesEnabled: true,
            journalDirectory: journalDir
        )
        task.deletedAt = Date(timeIntervalSince1970: 3_000)
        try context.save()
        _ = try await store.pushPending(context: context, token: "t", scope: "undo-delete")

        task.deletedAt = nil
        try context.save()
        let pending = try ContentSyncStore.pendingChanges(
            in: context,
            journal: SyncJournalStore(directory: journalDir, scope: "undo-delete").load()
        )
        let change = try #require(pending.first { $0.entityId == task.id.uuidString })
        #expect(change.op == "upsert")
        #expect(change.payload["deletedAt"] == .null)
    }

    @Test func editMadeWhilePushResponseIsInFlightRemainsPending() async throws {
        let context = try makeContext()
        let task = TodoTask(title: "上传中的旧标题", createdAt: Date(timeIntervalSince1970: 1_000))
        context.insert(task)
        try context.save()

        let journalDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let api = SyncAPIMock()
        api.onPush = {
            task.title = "响应前的新标题"
            try context.save()
        }
        let store = ContentSyncStore(
            api: api,
            defaults: UserDefaults(suiteName: "content-sync-tests")!,
            forcesEnabled: true,
            journalDirectory: journalDir
        )
        _ = try await store.pushPending(context: context, token: "t", scope: "in-flight-edit")

        let pending = try ContentSyncStore.pendingChanges(
            in: context,
            journal: SyncJournalStore(directory: journalDir, scope: "in-flight-edit").load()
        )
        let change = try #require(pending.first { $0.entityId == task.id.uuidString })
        #expect(change.payload["title"] == .string("响应前的新标题"))
        #expect(store.pendingCount == 1)
        #expect(store.message?.contains("仍有 1 项新变更待同步") == true)
    }

    @Test func applyPurgedTombstonesOnlyDeletesExistingEntitiesAndPreservesHistory() throws {
        let context = try makeContext()
        let createdAt = Date(timeIntervalSince1970: 1_000)
        let completedAt = Date(timeIntervalSince1970: 1_500)
        let goal = Goal(name: "保留名称", iconName: "book.closed", createdAt: createdAt)
        let task = TodoTask(
            title: "保留标题",
            createdAt: createdAt,
            completedAt: completedAt,
            goal: goal
        )
        let session = TimingSession(
            taskID: task.id,
            taskTitleSnapshot: "历史任务快照",
            goalIDSnapshot: goal.id,
            goalNameSnapshot: "历史目标快照",
            startedAt: Date(timeIntervalSince1970: 1_100),
            endedAt: Date(timeIntervalSince1970: 1_200),
            activeIntervals: [TimingInterval(
                startedAt: Date(timeIntervalSince1970: 1_100),
                endedAt: Date(timeIntervalSince1970: 1_200)
            )],
            accumulatedSeconds: 100,
            state: .finished
        )
        context.insert(goal)
        context.insert(task)
        context.insert(session)
        try context.save()

        let deletedAt = 5_000
        let entities = [
            SyncEntityPayload(
                entityType: "goal", entityId: goal.id.uuidString, version: 4,
                serverSeq: 10, updatedAt: deletedAt, deletedAt: deletedAt, payload: [:]
            ),
            SyncEntityPayload(
                entityType: "task", entityId: task.id.uuidString, version: 3,
                serverSeq: 11, updatedAt: deletedAt, deletedAt: deletedAt, payload: [:]
            ),
            SyncEntityPayload(
                entityType: "goal", entityId: UUID().uuidString, version: 2,
                serverSeq: 12, updatedAt: deletedAt, deletedAt: deletedAt, payload: [:]
            ),
            SyncEntityPayload(
                entityType: "task", entityId: UUID().uuidString, version: 2,
                serverSeq: 13, updatedAt: deletedAt, deletedAt: deletedAt, payload: [:]
            )
        ]
        try ContentSyncStore.apply(entities: entities, in: context)

        let goals = try context.fetch(FetchDescriptor<Goal>())
        let tasks = try context.fetch(FetchDescriptor<TodoTask>())
        let sessions = try context.fetch(FetchDescriptor<TimingSession>())
        #expect(goals.count == 1)
        #expect(tasks.count == 1)
        #expect(goals[0].name == "保留名称")
        #expect(goals[0].iconName == "book.closed")
        #expect(goals[0].createdAt == createdAt)
        #expect(goals[0].deletedAt == Date(timeIntervalSince1970: TimeInterval(deletedAt)))
        #expect(tasks[0].title == "保留标题")
        #expect(tasks[0].createdAt == createdAt)
        #expect(tasks[0].completedAt == completedAt)
        #expect(tasks[0].deletedAt == Date(timeIntervalSince1970: TimeInterval(deletedAt)))
        #expect(tasks[0].goal == nil)
        #expect(sessions.count == 1)
        #expect(sessions[0].taskTitleSnapshot == "历史任务快照")
        #expect(sessions[0].goalNameSnapshot == "历史目标快照")
    }

    @Test func conflictKeepLocalUsesCloudVersionPlusOne() async throws {
        let context = try makeContext()
        let task = try TaskService.create(title: "本机较新", in: context)
        let journalDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let api = ConflictAPIMock()
        let store = ContentSyncStore(
            api: api,
            defaults: UserDefaults(suiteName: "content-sync-tests")!,
            forcesEnabled: true,
            journalDirectory: journalDir
        )
        _ = try await store.pushPending(context: context, token: "t", scope: "account-c")
        #expect(store.conflicts.count == 1)
        let conflict = try #require(store.conflicts.first)
        #expect(conflict.serverVersion == 3)
        await store.resolveConflict(conflict, keepLocal: true, context: context, token: "t", scope: "account-c")
        #expect(api.lastPushVersion == 4)
        #expect(store.conflicts.isEmpty)
        #expect(store.message?.contains("本机") == true)
        _ = task
    }

    @Test func conflictUseCloudAppliesServerPayload() async throws {
        let context = try makeContext()
        let task = try TaskService.create(title: "本机旧", in: context)
        let journalDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let api = ConflictAPIMock()
        let store = ContentSyncStore(
            api: api,
            defaults: UserDefaults(suiteName: "content-sync-tests")!,
            forcesEnabled: true,
            journalDirectory: journalDir
        )
        _ = try await store.pushPending(context: context, token: "t", scope: "account-d")
        let conflict = try #require(store.conflicts.first)
        await store.resolveConflict(conflict, keepLocal: false, context: context, token: "t", scope: "account-d")
        let updated = try context.fetch(FetchDescriptor<TodoTask>()).first { $0.id == task.id }
        #expect(updated?.title == "云端较新")
        #expect(store.conflicts.isEmpty)
    }

    @Test func purgedConflictKeepLocalDoesNotRetryUnrecoverableIdentifier() async throws {
        let context = try makeContext()
        let task = try TaskService.create(title: "本机副本", in: context)
        let journalDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let api = PurgedConflictAPIMock()
        let store = ContentSyncStore(
            api: api,
            defaults: UserDefaults(suiteName: "content-sync-tests")!,
            forcesEnabled: true,
            journalDirectory: journalDir
        )
        _ = try await store.pushPending(context: context, token: "t", scope: "purged-local")
        let conflict = try #require(store.conflicts.first)

        await store.resolveConflict(conflict, keepLocal: true, context: context, token: "t", scope: "purged-local")

        #expect(api.pushed.count == 1)
        #expect(task.deletedAt == nil)
        #expect(store.conflicts.isEmpty)
        #expect(store.localOnlyCount == 1)
        #expect(store.message == "云端记录已永久删除；保留的副本仅存于本机，不再上传。")
        let pending = try ContentSyncStore.pendingChanges(
            in: context,
            journal: SyncJournalStore(directory: journalDir, scope: "purged-local").load()
        )
        #expect(pending.isEmpty)

        let sent = try await store.pushPending(context: context, token: "t", scope: "purged-local")
        #expect(sent == 0)
        #expect(api.pushed.count == 1)
        #expect(store.message?.contains("1 项副本仅存于本机，不再上传") == true)
    }

    @Test func purgedConflictUseCloudMarksExistingDeletedWithoutPlaceholderOrLoop() async throws {
        let context = try makeContext()
        let createdAt = Date(timeIntervalSince1970: 1_000)
        let completedAt = Date(timeIntervalSince1970: 1_500)
        let task = TodoTask(title: "旧任务", createdAt: createdAt, completedAt: completedAt)
        context.insert(task)
        try context.save()
        let journalDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let api = PurgedConflictAPIMock()
        let store = ContentSyncStore(
            api: api,
            defaults: UserDefaults(suiteName: "content-sync-tests")!,
            forcesEnabled: true,
            journalDirectory: journalDir
        )
        _ = try await store.pushPending(context: context, token: "t", scope: "purged-cloud")
        let conflict = try #require(store.conflicts.first)

        await store.resolveConflict(conflict, keepLocal: false, context: context, token: "t", scope: "purged-cloud")

        #expect(task.title == "旧任务")
        #expect(task.createdAt == createdAt)
        #expect(task.completedAt == completedAt)
        #expect(task.deletedAt == Date(timeIntervalSince1970: 4_000))
        #expect(store.conflicts.isEmpty)
        #expect(store.localOnlyCount == 0)
        let pending = try ContentSyncStore.pendingChanges(
            in: context,
            journal: SyncJournalStore(directory: journalDir, scope: "purged-cloud").load()
        )
        #expect(pending.isEmpty)
    }

    @MainActor private final class ConflictAPIMock: ContentSyncServing, @unchecked Sendable {
        var lastPushVersion: Int?
        private var didConflict = false

        func push(token: String, changes: [SyncChangePayload]) async throws -> SyncPushResponse {
            lastPushVersion = changes.first?.version
            guard let change = changes.first else {
                return SyncPushResponse(applied: [], conflicts: [], serverTime: 0)
            }
            if !didConflict {
                didConflict = true
                return SyncPushResponse(
                    applied: [],
                    conflicts: [SyncConflictItem(
                        clientOpId: change.clientOpId,
                        entityType: change.entityType,
                        entityId: change.entityId,
                        serverVersion: 3,
                        serverUpdatedAt: 2_000,
                        serverDeletedAt: nil,
                        serverPayload: [
                            "title": .string("云端较新"),
                            "createdAt": .int(1_000),
                            "completedAt": .null,
                            "deletedAt": .null,
                            "goalId": .null
                        ]
                    )],
                    serverTime: 0
                )
            }
            return SyncPushResponse(
                applied: [SyncAppliedItem(
                    clientOpId: change.clientOpId,
                    entityType: change.entityType,
                    entityId: change.entityId,
                    version: change.version,
                    serverSeq: change.version,
                    deduped: false
                )],
                conflicts: [],
                serverTime: 0
            )
        }

        func pull(token: String, cursor: Int, limit: Int) async throws -> SyncPullResponse {
            SyncPullResponse(entities: [], cursor: cursor, hasMore: false)
        }

        func status(token: String) async throws -> SyncStatusResponse {
            SyncStatusResponse(accountId: "a", latestSeq: 0, softDeletedCount: 0, syncEnabled: true)
        }
    }

    @MainActor private final class PurgedConflictAPIMock: ContentSyncServing, @unchecked Sendable {
        var pushed: [[SyncChangePayload]] = []

        func push(token: String, changes: [SyncChangePayload]) async throws -> SyncPushResponse {
            pushed.append(changes)
            guard let change = changes.first else {
                return SyncPushResponse(applied: [], conflicts: [], serverTime: 0)
            }
            return SyncPushResponse(
                applied: [],
                conflicts: [SyncConflictItem(
                    clientOpId: change.clientOpId,
                    entityType: change.entityType,
                    entityId: change.entityId,
                    serverVersion: 5,
                    serverUpdatedAt: 4_000,
                    serverDeletedAt: 4_000,
                    serverPayload: [:]
                )],
                serverTime: 4_000
            )
        }

        func pull(token: String, cursor: Int, limit: Int) async throws -> SyncPullResponse {
            SyncPullResponse(entities: [], cursor: cursor, hasMore: false)
        }

        func status(token: String) async throws -> SyncStatusResponse {
            SyncStatusResponse(accountId: "a", latestSeq: 0, softDeletedCount: 0, syncEnabled: true)
        }
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
