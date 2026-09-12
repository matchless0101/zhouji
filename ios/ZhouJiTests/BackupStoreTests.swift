import Foundation
import SwiftData
import Testing
@testable import ZhouJi

@MainActor
struct BackupStoreTests {
    @Test
    func exportEncodeDecodeRestoreRoundTripPreservesFacts() throws {
        let source = try makeContext()
        let goal = try GoalService.create(name: "毕业论文", icon: .book, at: date(1_000), in: source)
        let task = try TaskService.create(title: "写摘要", goal: goal, at: date(2_000), in: source)
        try TaskService.setCompleted(task, completed: true, at: date(3_000), in: source)
        let deleted = try TaskService.create(title: "废弃提纲", goal: goal, at: date(2_500), in: source)
        try TaskService.softDelete(deleted, at: date(4_000), in: source)

        let start = date(5_000)
        let end = date(5_600)
        let session = TimingSession(
            taskID: task.id,
            taskTitleSnapshot: task.title,
            goalIDSnapshot: goal.id,
            goalNameSnapshot: goal.name,
            startedAt: start,
            endedAt: end,
            activeIntervals: [TimingInterval(startedAt: start, endedAt: end)],
            accumulatedSeconds: 600,
            state: .finished
        )
        source.insert(session)
        try source.save()

        let document = try BackupStore.exportDocument(from: source, applicationVersion: "1.0", exportedAt: date(10_000))
        let data = try BackupStore.encode(document)
        let decoded = try BackupStore.decode(data)
        #expect(decoded == document)

        let empty = try makeContext()
        let result = try BackupStore.restore(decoded, in: empty)
        #expect(result.verifiedGoalCount == 1)
        #expect(result.verifiedTaskCount == 2)
        #expect(result.verifiedSessionCount == 1)

        let restoredTasks = try empty.fetch(FetchDescriptor<TodoTask>())
        let restoredTask = try #require(restoredTasks.first { $0.id == task.id })
        let restoredDeleted = try #require(restoredTasks.first { $0.id == deleted.id })
        let restoredSession = try #require(empty.fetch(FetchDescriptor<TimingSession>()).first)

        #expect(restoredTask.title == "写摘要")
        #expect(restoredTask.completedAt == date(3_000))
        #expect(restoredTask.goal?.id == goal.id)
        #expect(restoredDeleted.deletedAt == date(4_000))
        #expect(restoredSession.accumulatedSeconds == 600)
        #expect(restoredSession.activeIntervals.count == 1)
        #expect(restoredSession.taskTitleSnapshot == "写摘要")
    }

    @Test
    func restoreUpdatesExistingIdsAndDoesNotDeleteMissingLocalRows() throws {
        let context = try makeContext()
        let keepLocal = try TaskService.create(title: "仅本机", in: context)
        let shared = try TaskService.create(title: "旧标题", in: context)
        let document = ZhouJiBackupDocument(
            schemaVersion: 1,
            format: BackupStore.formatIdentifier,
            exportedAt: date(1),
            applicationVersion: "1.0",
            goals: [],
            tasks: [
                BackupTask(id: shared.id, title: "备份标题", createdAt: shared.createdAt, completedAt: nil, deletedAt: nil, goalID: nil)
            ],
            timingSessions: []
        )

        let preview = try BackupStore.preview(document, in: context)
        #expect(preview.tasksInsert == 0)
        #expect(preview.tasksUpdate == 1)
        _ = try BackupStore.restore(document, in: context)

        let tasks = try context.fetch(FetchDescriptor<TodoTask>())
        #expect(tasks.count == 2)
        #expect(try #require(tasks.first { $0.id == shared.id }).title == "备份标题")
        #expect(try #require(tasks.first { $0.id == keepLocal.id }).title == "仅本机")
    }

    @Test
    func decodeRejectsForeignFormatNewerSchemaEmptyAndBrokenRelations() throws {
        #expect(throws: BackupError.self) {
            try BackupStore.decode(Data("{}".utf8))
        }

        let newer = """
        {"schemaVersion":99,"format":"zhouji-backup","exportedAt":"2026-01-01T00:00:00Z",
         "applicationVersion":"1.0","goals":[],"tasks":[],"timingSessions":[]}
        """
        // Empty arrays fail empty check after schema; craft non-empty with bad schema.
        let newerWithRows = """
        {"schemaVersion":99,"format":"zhouji-backup","exportedAt":"2026-01-01T00:00:00Z",
         "applicationVersion":"1.0",
         "goals":[{"id":"11111111-1111-1111-1111-111111111111","name":"目标","iconName":null,
                   "createdAt":"2026-01-01T00:00:00Z","deletedAt":null}],
         "tasks":[],
         "timingSessions":[]}
        """
        #expect(throws: BackupError.self) {
            try BackupStore.decode(Data(newerWithRows.utf8))
        }

        let brokenRelation = """
        {"schemaVersion":1,"format":"zhouji-backup","exportedAt":"2026-01-01T00:00:00Z",
         "applicationVersion":"1.0",
         "goals":[],
         "tasks":[{"id":"22222222-2222-2222-2222-222222222222","title":"任务","createdAt":"2026-01-01T00:00:00Z",
                   "completedAt":null,"deletedAt":null,
                   "goalID":"33333333-3333-3333-3333-333333333333"}],
         "timingSessions":[]}
        """
        #expect(throws: BackupError.self) {
            try BackupStore.decode(Data(brokenRelation.utf8))
        }
        _ = newer
    }

    private func date(_ interval: TimeInterval) -> Date {
        Date(timeIntervalSince1970: interval)
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
