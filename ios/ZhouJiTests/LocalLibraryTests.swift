import Foundation
import SwiftData
import Testing
@testable import ZhouJi

@MainActor struct LocalLibraryTests {
    private func fixtures() throws -> (LocalLibraryStore, URL, UserDefaults) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let defaults = try #require(UserDefaults(suiteName: UUID().uuidString))
        let guest = try ModelContainer(for: Goal.self, TodoTask.self, TimingSession.self,
            configurations: ModelConfiguration(url: directory.appendingPathComponent("default.store")))
        return (try LocalLibraryStore(guest: guest, directory: directory, defaults: defaults), directory, defaults)
    }
    private func titles(_ store: LocalLibraryStore) throws -> [String] {
        try store.current.container.mainContext.fetch(FetchDescriptor<TodoTask>()).map(\.title).sorted()
    }
    private func login(_ id: String, _ store: LocalLibraryStore) throws {
        let prepared = try store.prepareLogin(accountID: id)
        store.completeLogin(accountID: id, prepared: prepared)
    }

    @Test func oldGuestDataAccountsAndRestartStaySeparate() throws {
        let (store, directory, defaults) = try fixtures()
        let guest = store.current.container
        let goal = try GoalService.create(name: "旧目标", in: guest.mainContext)
        let original = try TaskService.create(title: "游客历史", goal: goal, in: guest.mainContext)
        try login("A", store)
        #expect(try titles(store).isEmpty)
        #expect(try BackupStore.readFile(directory.appendingPathComponent("before-isolation.json")).tasks[0].id == original.id)
        let accountA = store.current.container
        _ = try TaskService.create(title: "A 的任务", in: accountA.mainContext)
        try login("B", store)
        #expect(try titles(store).isEmpty)
        // Same stable ID in another account must not deduplicate or change the guest row.
        store.current.container.mainContext.insert(TodoTask(id: original.id, title: "B 的任务"))
        try store.current.container.mainContext.save()
        #expect(original.title == "游客历史" && original.goal?.id == goal.id)
        let fresh = try LocalLibraryStore(guest: guest, directory: directory, defaults: defaults)
        #expect(try titles(fresh) == ["B 的任务"])
        try fresh.restoreAuthentication(accountID: "B")
        fresh.completeLogout(prepared: try fresh.prepareLogout())
        #expect(try titles(fresh) == ["游客历史"])
        try login("A", fresh)
        #expect(try titles(fresh) == ["A 的任务"])
        #expect(fresh.current.timer.activeSession == nil)
    }

    @Test func timerBlocksSwitchAndExpiryDoesNotReassignFacts() throws {
        let (store, _, _) = try fixtures()
        try login("A", store)
        let task = try TaskService.create(title: "运行任务", in: store.current.container.mainContext)
        let timer = store.current.timer
        _ = timer.requestStart(for: task)
        #expect(throws: LibraryError.self) { try store.prepareLogin(accountID: "B") }
        #expect(timer.pause())
        #expect(throws: LibraryError.self) { try store.prepareLogout() }
        store.authenticationExpired()
        #expect(store.authenticatedScope == nil)
        #expect(store.current.scope == LibraryScope.account("A"))
        #expect(store.current.timer === timer)
        #expect(try titles(store) == ["运行任务"])
        #expect(timer.finishActiveSession())
        store.completeLogout(prepared: try store.prepareLogout())
        #expect(store.current.timer.activeSession == nil)
        #expect(try titles(store).isEmpty)
        try login("A", store)
        #expect(try store.current.container.mainContext.fetchCount(FetchDescriptor<TimingSession>()) == 1)
    }

    @Test func accountBackupsAndProtectionCopiesCannotCrossScopes() throws {
        let (store, _, _) = try fixtures()
        let guest = store.current.container.mainContext
        try login("A", store)
        let a = store.current.container.mainContext
        _ = try TaskService.create(title: "只属 A", in: a)
        let backup = try BackupStore.decode(BackupStore.encode(BackupStore.exportDocument(from: a)))
        #expect(backup.dataScope == LibraryScope.account("A"))
        #expect(throws: BackupError.self) { try BackupStore.restore(backup, in: guest) }
        try login("B", store)
        let b = store.current.container.mainContext
        #expect(throws: BackupError.self) { try BackupStore.preview(backup, in: b) }
        #expect(throws: BackupError.self) { try BackupStore.restore(backup, in: b) }
        #expect(BackupSafetyStore.fileURL(in: a) != BackupSafetyStore.fileURL(in: b))
        #expect(BackupSafetyStore.fileURL(in: a) != BackupSafetyStore.fileURL(in: guest))
        try login("A", store)
        _ = try BackupStore.restore(backup, in: store.current.container.mainContext, protectionWriter: { _ in })
        #expect(try titles(store) == ["只属 A"])
    }

    @Test func openingFailurePreservesGuestAndMissingSelectedStoreDoesNotCreateEmptyReplacement() throws {
        let (store, directory, defaults) = try fixtures()
        let guest = store.current.container
        _ = try TaskService.create(title: "不能丢", in: guest.mainContext)
        let broken = try LocalLibraryStore(guest: guest, directory: directory, defaults: defaults,
            openAccount: { _, _, _ in throw CocoaError(.fileWriteOutOfSpace) })
        #expect(throws: CocoaError.self) { try broken.prepareLogin(accountID: "A") }
        #expect(try titles(broken) == ["不能丢"])
        defaults.set(LibraryScope.account("missing"), forKey: "localLibrary.selectedScope")
        #expect(throws: LibraryError.self) { try LocalLibraryStore(guest: guest, directory: directory, defaults: defaults) }
        #expect(try guest.mainContext.fetchCount(FetchDescriptor<TodoTask>()) == 1)
    }

    @Test func deletionBackupBelongsToAccountEvenWhenViewingGuest() throws {
        let (store, _, _) = try fixtures()
        try login("A", store)
        _ = try TaskService.create(title: "注销前", in: store.current.container.mainContext)
        store.showGuest()
        _ = try TaskService.create(title: "游客", in: store.current.container.mainContext)
        let url = try #require(try store.prepareDeletionBackup())
        let backup = try BackupStore.readFile(url)
        #expect(backup.tasks.map(\.title) == ["注销前"])
        #expect(backup.dataScope == LibraryScope.account("A"))
        store.retainDeletedBackup(url)
        store.completeLogout(prepared: try store.prepareLogout())
        #expect(try titles(store) == ["游客"])
        #expect(store.deletedBackupURL == url)
    }
}
