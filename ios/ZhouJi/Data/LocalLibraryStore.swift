import CryptoKit
import Foundation
import Observation
import SwiftData

/// A scope describes local storage, never permission to access a server account.
enum LibraryScope {
    static let guest = "local"
    static func account(_ id: String) -> String {
        "account-" + SHA256.hash(data: Data(id.utf8)).map { String(format: "%02x", $0) }.joined()
    }
    static func isValid(_ value: String) -> Bool {
        value == guest || (value.hasPrefix("account-") && value.count == 72
            && value.dropFirst(8).allSatisfy { "0123456789abcdef".contains($0) })
    }
    @MainActor static func of(_ context: ModelContext) -> String {
        let name = context.container.configurations.first?.name ?? ""
        return name.hasPrefix("account-") && isValid(name) ? name : guest
    }
}

enum LibraryError: LocalizedError {
    case activeTimer, unavailable, wrongAccount
    var errorDescription: String? {
        switch self {
        case .activeTimer: "请先结束当前计时，再切换记录或退出账户。暂停的计时也需要先结束。"
        case .unavailable: "无法打开本机记录，原数据已保留。请检查可用空间后重试。"
        case .wrongAccount: "请登录对应账户后再打开这份记录。"
        }
    }
}

@MainActor
final class LocalLibrary {
    let scope: String
    let container: ModelContainer
    let timer: TimerController
    init(scope: String, container: ModelContainer) {
        self.scope = scope
        self.container = container
        timer = TimerController()
        timer.configure(with: container.mainContext)
    }
}

@MainActor @Observable
final class LocalLibraryStore {
    private(set) var current: LocalLibrary
    private(set) var authenticatedScope: String?
    private(set) var deletedBackupURL: URL?
    var message: String?
    private let guest: ModelContainer
    private let directory: URL
    private let defaults: UserDefaults
    private let inMemory: Bool
    private var containers: [String: ModelContainer] = [:]
    private let openAccount: @MainActor (String, URL, Bool) throws -> ModelContainer
    private static let selectionKey = "localLibrary.selectedScope"
    private static let deletedKey = "localLibrary.deletedBackupScope"

    init(guest: ModelContainer, directory: URL = URL.applicationSupportDirectory.appendingPathComponent("AccountLibraries"),
         defaults: UserDefaults = .standard, inMemory: Bool = false,
         openAccount: @escaping @MainActor (String, URL, Bool) throws -> ModelContainer = LocalLibraryStore.open) throws {
        self.guest = guest
        self.directory = directory
        self.defaults = defaults
        self.inMemory = inMemory
        self.openAccount = openAccount
        current = LocalLibrary(scope: LibraryScope.guest, container: guest)
        // A cached account library remains its own library after expiry; it never becomes guest data.
        if !inMemory, let scope = defaults.string(forKey: Self.selectionKey), scope != LibraryScope.guest {
            guard LibraryScope.isValid(scope), FileManager.default.fileExists(atPath: directory.appendingPathComponent(scope + ".store").path) else {
                throw LibraryError.unavailable
            }
            current = LocalLibrary(scope: scope, container: try container(for: scope))
        }
        if !inMemory, let scope = defaults.string(forKey: Self.deletedKey), LibraryScope.isValid(scope) {
            let url = directory.appendingPathComponent("deleted-" + scope + ".json")
            if FileManager.default.fileExists(atPath: url.path) { deletedBackupURL = url }
        }
    }

    private static func open(scope: String, url: URL, inMemory: Bool) throws -> ModelContainer {
        let schema = Schema([Goal.self, TodoTask.self, TimingSession.self])
        let config = inMemory ? ModelConfiguration(scope, schema: schema, isStoredInMemoryOnly: true)
            : ModelConfiguration(scope, schema: schema, url: url)
        return try ModelContainer(for: schema, configurations: [config])
    }

    private func container(for scope: String) throws -> ModelContainer {
        if scope == LibraryScope.guest { return guest }
        if let container = containers[scope] { return container }
        guard LibraryScope.isValid(scope) else { throw LibraryError.wrongAccount }
        if !inMemory { try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true) }
        let container = try openAccount(scope, directory.appendingPathComponent(scope + ".store"), inMemory)
        containers[scope] = container
        return container
    }

    func prepareSwitch(to scope: String) throws -> LocalLibrary {
        if current.scope == scope { return current }
        let context = current.container.mainContext
        if try context.fetch(FetchDescriptor<TimingSession>()).contains(where: { $0.state != .finished }) {
            throw LibraryError.activeTimer
        }
        try context.save()
        // Keep the original default.store as the guest library; no renaming, copying SQLite sidecars or reassigning rows.
        if !inMemory, current.scope == LibraryScope.guest {
            let snapshot = directory.appendingPathComponent("before-isolation.json")
            if !FileManager.default.fileExists(atPath: snapshot.path) {
                let data = try BackupStore.encode(BackupStore.exportDocument(from: context))
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                try data.write(to: snapshot, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            }
        }
        return LocalLibrary(scope: scope, container: try container(for: scope))
    }

    private func select(_ library: LocalLibrary) {
        current = library
        if !inMemory { defaults.set(library.scope, forKey: Self.selectionKey) }
        message = nil
    }

    func prepareLogin(accountID: String) throws -> LocalLibrary {
        try prepareSwitch(to: LibraryScope.account(accountID))
    }

    func completeLogin(accountID: String, prepared: LocalLibrary) {
        authenticatedScope = LibraryScope.account(accountID)
        select(prepared)
        message = "已打开此账户的本机记录。原有游客记录单独保留，未自动合并或上传。"
    }

    func restoreAuthentication(accountID: String) throws {
        let scope = LibraryScope.account(accountID)
        // A deliberately selected guest library remains selected across launches.
        if current.scope != LibraryScope.guest && current.scope != scope {
            select(try prepareSwitch(to: scope))
        }
        authenticatedScope = scope
    }

    func authenticationExpired() { authenticatedScope = nil }

    func prepareLogout() throws -> LocalLibrary { try prepareSwitch(to: LibraryScope.guest) }
    func completeLogout(prepared: LocalLibrary) {
        authenticatedScope = nil
        select(prepared)
    }

    func showGuest() {
        do { select(try prepareSwitch(to: LibraryScope.guest)) }
        catch { message = error.localizedDescription }
    }
    func showAccount() {
        do {
            guard let scope = authenticatedScope else { throw LibraryError.wrongAccount }
            select(try prepareSwitch(to: scope))
        } catch { message = error.localizedDescription }
    }

    /// Keep an explicitly exportable copy before deleting the identity needed to reopen this library.
    func prepareDeletionBackup() throws -> URL? {
        guard let scope = authenticatedScope else { return nil }
        let context = try container(for: scope).mainContext
        try context.save()
        let data = try BackupStore.encode(BackupStore.exportDocument(from: context))
        let url = directory.appendingPathComponent("deleted-" + scope + ".json")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        return url
    }
    func retainDeletedBackup(_ url: URL?) {
        deletedBackupURL = url
        if let url, !inMemory {
            defaults.set(url.deletingPathExtension().lastPathComponent.replacingOccurrences(of: "deleted-", with: ""), forKey: Self.deletedKey)
        }
    }
}
