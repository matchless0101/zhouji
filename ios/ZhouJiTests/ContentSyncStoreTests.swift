import Foundation
import SwiftData
import Testing
@testable import ZhouJi

@MainActor private final class SyncAPIMock: ContentSyncServing, @unchecked Sendable {
    var pushed: [[SyncChangePayload]] = []
    var pullPages: [SyncPullResponse] = []
    var status = SyncStatusResponse(accountId: "a1", latestSeq: 0, softDeletedCount: 0, syncEnabled: true)

    func push(token: String, changes: [SyncChangePayload]) async throws -> SyncPushResponse {
        pushed.append(changes)
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
        let second = try await ContentSyncStore.pendingChanges(
            in: source,
            journal: SyncJournalStore(directory: journalDir, scope: "account-test").load()
        )
        #expect(second.isEmpty)
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
