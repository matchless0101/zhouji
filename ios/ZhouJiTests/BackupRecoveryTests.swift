import Foundation
import SwiftData
import Testing
@testable import ZhouJi

@MainActor struct BackupRecoveryTests {
    private func context(url: URL? = nil) throws -> ModelContext {
        let configuration = url.map { ModelConfiguration(url: $0) } ?? ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Goal.self, TodoTask.self, TimingSession.self, configurations: configuration)
        let context = ModelContext(container)
        context.autosaveEnabled = false
        return context
    }
    private func date(_ value: Double) -> Date { Date(timeIntervalSince1970: value) }
    private func fixture() throws -> (ModelContext, TodoTask, TimingSession) {
        let db = try context()
        let task = try TaskService.create(title: "备份计时", at: date(100), in: db)
        let session = TimingSession(taskID: task.id, taskTitleSnapshot: task.title,
            startedAt: date(200.125), endedAt: date(201.875),
            activeIntervals: [.init(startedAt: date(200.125), endedAt: date(201.875))],
            accumulatedSeconds: 1.75, state: .finished)
        db.insert(session)
        try db.save()
        return (db, task, session)
    }

    @Test func runningBackupFreezesAtExportAndRestoresPausedWithoutChangingLiveTimer() throws {
        let db = try context()
        let task = try TaskService.create(title: "跨夜任务", at: date(100), in: db)
        let session = TimingSession(taskID: task.id, taskTitleSnapshot: task.title, startedAt: date(200),
            activeIntervals: [.init(startedAt: date(200), endedAt: date(210))], accumulatedSeconds: 10,
            runningStartedAt: date(86_395.125), state: .running)
        db.insert(session)
        try db.save()
        let backup = try BackupStore.exportDocument(from: db, exportedAt: date(86_405.875))
        #expect(session.state == .running && session.runningStartedAt == date(86_395.125))
        #expect(session.activeIntervals.count == 1 && session.accumulatedSeconds == 10)
        let decoded = try BackupStore.decode(BackupStore.encode(backup))
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let storeURL = folder.appendingPathComponent("restored.store")
        let target = try context(url: storeURL)
        _ = try BackupStore.restore(decoded, in: target, protectionWriter: { _ in })
        let reopened = try context(url: storeURL)
        let persisted = try BackupStore.exportDocument(from: reopened, exportedAt: backup.exportedAt)
        #expect(persisted == backup)
        let restoredSessions = try reopened.fetch(FetchDescriptor<TimingSession>())
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        let firstDay = StatisticsService.snapshot(tasks: [], sessions: restoredSessions,
            now: date(300_000), periodDate: date(500), calendar: calendar)
        let nextDay = StatisticsService.snapshot(tasks: [], sessions: restoredSessions,
            now: date(300_000), periodDate: date(86_410), calendar: calendar)
        #expect(firstDay.secondsToday == 14.875)
        #expect(nextDay.secondsToday == 5.875)
        let timer = TimerController(nowProvider: { self.date(300_000) })
        timer.configure(with: reopened)
        #expect(timer.activeSession?.state == .paused)
        #expect(timer.elapsed(at: date(300_000)) == 20.75)
        #expect(timer.activeSession?.activeIntervals.last?.endedAt == date(86_405.875))
    }

    @Test func versionTwoPreservesFractionalIntervalsAndLegacyRunningFileIsSafe() throws {
        let (db, _, session) = try fixture()
        let backup = try BackupStore.exportDocument(from: db, exportedAt: date(300))
        #expect(backup.schemaVersion == 2 && backup.dataScope == "local")
        let decoded = try BackupStore.decode(BackupStore.encode(backup))
        #expect(decoded == backup)
        session.startedAt = date(200)
        session.state = .running
        session.endedAt = nil
        session.runningStartedAt = date(220)
        session.activeIntervals = [.init(startedAt: date(200), endedAt: date(201))]
        session.accumulatedSeconds = 1.75 // v1's total retained fractions while its dates were rounded.
        let legacy = ZhouJiBackupDocument(schemaVersion: 1, format: BackupStore.formatIdentifier,
            exportedAt: date(230), applicationVersion: "old", goals: [],
            tasks: backup.tasks, timingSessions: [BackupTimingSession(session)])
        let restored = try BackupStore.decode(BackupStore.encode(legacy))
        #expect(restored.timingSessions[0].state == .paused)
        #expect(restored.timingSessions[0].accumulatedSeconds == 11)
        #expect(restored.timingSessions[0].runningStartedAt == nil)
    }

    @Test(arguments: ["reversed", "overlap", "total", "finished", "paused", "nan", "duplicate"])
    func invalidContentIsRejectedEvenWhenCallingRestoreDirectly(kind: String) throws {
        let (db, _, _) = try fixture()
        var backup = try BackupStore.exportDocument(from: db, exportedAt: date(300))
        switch kind {
        case "reversed": backup.timingSessions[0].activeIntervals = [.init(startedAt: date(202), endedAt: date(201))]
        case "overlap": backup.timingSessions[0].activeIntervals += [.init(startedAt: date(201), endedAt: date(203))]
        case "total": backup.timingSessions[0].accumulatedSeconds = 9_999
        case "finished": backup.timingSessions[0].endedAt = nil
        case "paused": backup.timingSessions[0].state = .paused
        case "nan": backup.timingSessions[0].accumulatedSeconds = .nan
        default: backup.timingSessions.append(backup.timingSessions[0])
        }
        let target = try context()
        var protectionCalled = false
        #expect(throws: BackupError.self) {
            try BackupStore.restore(backup, in: target, protectionWriter: { _ in protectionCalled = true })
        }
        #expect(!protectionCalled)
        #expect(try target.fetchCount(FetchDescriptor<TodoTask>()) == 0)
        #expect(try target.fetchCount(FetchDescriptor<TimingSession>()) == 0)
        #expect(!target.hasChanges)
    }

    @Test func saveFailureRollsBackUpdatesInsertsAndRelationshipsOnDisk() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        // The simulator owns this temporary store; do not unlink SQLite files while a container is alive.
        let url = folder.appendingPathComponent("test.store")
        let target = try context(url: url)
        let goal = try GoalService.create(name: "原目标", at: date(1), in: target)
        let task = try TaskService.create(title: "原任务", goal: goal, at: date(2), in: target)
        let original = try BackupStore.exportDocument(from: target, exportedAt: date(500))
        let replacement = ZhouJiBackupDocument(schemaVersion: 2, format: BackupStore.formatIdentifier,
            exportedAt: date(500), applicationVersion: "test", goals: [
                BackupGoal(id: goal.id, name: "被覆盖", iconName: nil, createdAt: date(1), deletedAt: nil)],
            tasks: [BackupTask(id: task.id, title: "被覆盖", createdAt: date(2), completedAt: nil, deletedAt: nil, goalID: nil),
                    BackupTask(id: UUID(), title: "不应留下", createdAt: date(3), completedAt: nil, deletedAt: nil, goalID: goal.id)],
            timingSessions: [], dataScope: "local")
        var safety: Data?
        #expect(throws: BackupError.self) {
            try BackupStore.restore(replacement, in: target, protectionWriter: { safety = $0 }, saveChanges: { _ in
                throw CocoaError(.fileWriteOutOfSpace)
            })
        }
        let copy = try BackupStore.decode(#require(safety))
        #expect(copy.tasks == original.tasks && copy.goals == original.goals)
        #expect(!target.hasChanges)
        #expect(task.title == "原任务")
        #expect(task.goal?.id == goal.id)
        #expect(goal.name == "原目标")
        let reopened = try context(url: url)
        let persisted = try BackupStore.exportDocument(from: reopened, exportedAt: date(500))
        #expect(persisted == original)
    }

    @Test func failedProtectionAndChangedPreviewLeaveLocalDataUntouched() throws {
        let (source, _, _) = try fixture()
        let backup = try BackupStore.exportDocument(from: source)
        let target = try context()
        let existing = try TaskService.create(title: "保留", in: target)
        #expect(throws: BackupError.self) {
            try BackupStore.restore(backup, in: target, protectionWriter: { _ in throw CocoaError(.fileWriteOutOfSpace) })
        }
        #expect(try target.fetchCount(FetchDescriptor<TodoTask>()) == 1)
        let expected = try BackupStore.exportDocument(from: target)
        existing.title = "预览之后修改"
        #expect(throws: BackupError.self) {
            try BackupStore.restore(backup, in: target, expectedContent: expected, protectionWriter: { _ in })
        }
        #expect(existing.title == "预览之后修改")
    }

    @Test func runningOrPausedLocalTimerBlocksRestoreAndReloadFindsImportedPause() throws {
        let (source, _, _) = try fixture()
        let backup = try BackupStore.exportDocument(from: source)
        let target = try context()
        let task = try TaskService.create(title: "现场计时", in: target)
        let timer = TimerController()
        timer.configure(with: target)
        _ = timer.requestStart(for: task)
        #expect(throws: BackupError.self) { try BackupStore.preview(backup, in: target) }
        #expect(timer.pause())
        #expect(throws: BackupError.self) { try BackupStore.restore(backup, in: target, protectionWriter: { _ in }) }
        #expect(timer.finishActiveSession())
        var pause = backup
        pause.timingSessions[0].state = .paused
        pause.timingSessions[0].endedAt = nil
        _ = try BackupStore.restore(pause, in: target, protectionWriter: { _ in })
        timer.reloadAfterBackupRestore()
        #expect(timer.activeSession?.state == .paused)
    }

    @Test func unknownVersionsAccountScopeAndOversizeFilesAreRejected() throws {
        let (source, _, _) = try fixture()
        let backup = try BackupStore.exportDocument(from: source)
        let encoded = try BackupStore.encode(backup)
        let object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        for version in [0, -1, 99] {
            var changed = object
            changed["schemaVersion"] = version
            #expect(throws: BackupError.self) { try BackupStore.decode(JSONSerialization.data(withJSONObject: changed)) }
        }
        var scoped = object
        scoped["dataScope"] = "account"
        #expect(throws: BackupError.self) { try BackupStore.decode(JSONSerialization.data(withJSONObject: scoped)) }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        try Data(repeating: 32, count: BackupStore.maximumBytes + 1).write(to: url)
        #expect(throws: BackupError.self) { try BackupStore.readFile(url) }
    }
}
