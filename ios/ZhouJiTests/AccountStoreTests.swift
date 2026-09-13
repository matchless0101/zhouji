import Foundation
import SwiftData
import Testing
@testable import ZhouJi

private actor AccountStub: AccountServing {
    var fails = false
    var expired = false
    var logoutCalls = 0
    var deleteCalls = 0
    var profile = AppAccount(id: "test-account", provider: "apple")
    let value = AccountSession(token: "test-token", expiresAt: Date.now.timeIntervalSince1970 + 3600,
                               account: AppAccount(id: "test-account", provider: "apple"))
    func setFailure(_ value: Bool) { fails = value }
    func setExpired() { expired = true }
    func challenge() async throws -> LoginChallenge {
        if fails { throw AccountError.unavailable }
        return LoginChallenge(challenge: "test-challenge", nonce: "test-nonce", expiresAt: Date.now.timeIntervalSince1970 + 300)
    }
    func login(challenge: String, code: String, identityToken: String) async throws -> AccountSession {
        if fails { throw AccountError.unavailable }
        return value
    }
    func weChatChallenge() async throws -> LoginChallenge { try await challenge() }
    func loginWeChat(challenge: String, code: String) async throws -> AccountSession {
        if fails { throw AccountError.unavailable }
        profile = AppAccount(id: "wechat-account", provider: "wechat")
        return AccountSession(token: "wechat-token", expiresAt: Date.now.timeIntervalSince1970 + 3600, account: profile)
    }
    func account(token: String) async throws -> AppAccount {
        if expired { throw AccountError.expired }
        if fails { throw AccountError.unavailable }
        return profile
    }
    func updateProfile(token: String, nickname: String, avatar: String) async throws -> AppAccount {
        if expired { throw AccountError.expired }
        if fails { throw AccountError.unavailable }
        profile = AppAccount(id: "test-account", provider: "apple", nickname: nickname, avatar: avatar)
        return profile
    }
    func logout(token: String) async throws {
        logoutCalls += 1
        if fails { throw AccountError.unavailable }
    }
    func delete(token: String) async throws {
        deleteCalls += 1
        if fails { throw AccountError.unavailable }
    }
}

@MainActor private final class MemorySession: AccountSessionStoring {
    var value: AccountSession?
    var failsSave = false
    var failsRead = false
    func read() throws -> AccountSession? {
        if failsRead { throw AccountError.keychain }
        return value
    }
    func save(_ session: AccountSession) throws {
        if failsSave { throw AccountError.keychain }
        value = session
    }
    func clear() throws { value = nil }
}

@MainActor struct AccountStoreTests {
    @Test func authenticatedLibrariesRespectLoginFailureExpiryAndLogout() async throws {
        let guest = try ModelContainer(for: Goal.self, TodoTask.self, TimingSession.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let libraries = try LocalLibraryStore(guest: guest, inMemory: true)
        let api = AccountStub(), storage = MemorySession()
        let store = AccountStore(api: api, storage: storage, checksAppleCredential: false, libraries: libraries)
        _ = try TaskService.create(title: "游客历史", in: guest.mainContext)
        storage.failsSave = true
        await store.finishLogin(challenge: "c", code: "c", identityToken: "t", appleUser: "u")
        #expect(store.account == nil && libraries.current.scope == LibraryScope.guest)
        storage.failsSave = false
        await store.finishLogin(challenge: "c", code: "c", identityToken: "t", appleUser: "u")
        #expect(libraries.current.scope == LibraryScope.account("test-account"))
        let task = try TaskService.create(title: "账户计时", in: libraries.current.container.mainContext)
        _ = libraries.current.timer.requestStart(for: task)
        let calls = await api.logoutCalls
        await store.logout()
        #expect(store.account != nil)
        #expect(await api.logoutCalls == calls)
        #expect(libraries.current.timer.finishActiveSession())
        await api.setExpired()
        await store.restore()
        #expect(store.account == nil && libraries.authenticatedScope == nil)
        #expect(libraries.current.scope == LibraryScope.account("test-account"))
        await store.finishLogin(challenge: "c", code: "c", identityToken: "t", appleUser: "u")
        await store.logout()
        #expect(store.account == nil && libraries.current.scope == LibraryScope.guest)
        #expect(try guest.mainContext.fetch(FetchDescriptor<TodoTask>()).map(\.title) == ["游客历史"])
    }

    @Test func deletionBackupFailureStopsRequestAndServerFailureKeepsLibrary() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let guest = try ModelContainer(for: Goal.self, TodoTask.self, TimingSession.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let libraries = try LocalLibraryStore(guest: guest, directory: directory, inMemory: true)
        let api = AccountStub(), storage = MemorySession()
        let store = AccountStore(api: api, storage: storage, checksAppleCredential: false, libraries: libraries)
        await store.finishLogin(challenge: "c", code: "c", identityToken: "t", appleUser: "u")
        _ = try TaskService.create(title: "注销保护", in: libraries.current.container.mainContext)
        // A regular file at the destination directory reproduces a real protection-write failure.
        try Data().write(to: directory)
        await store.deleteAccount()
        #expect(await api.deleteCalls == 0)
        #expect(store.account != nil && libraries.current.scope != LibraryScope.guest)
        try FileManager.default.removeItem(at: directory)
        await api.setFailure(true)
        await store.deleteAccount()
        #expect(store.account != nil && libraries.current.scope != LibraryScope.guest)
        #expect(libraries.deletedBackupURL == nil)
        await api.setFailure(false)
        await store.deleteAccount()
        #expect(store.account == nil && libraries.current.scope == LibraryScope.guest)
        let url = try #require(libraries.deletedBackupURL)
        #expect(try BackupStore.readFile(url).tasks.map(\.title) == ["注销保护"])
    }

    @Test func profileSaveUpdatesIdentityAndSurvivesRestart() async {
        let api = AccountStub()
        let storage = MemorySession()
        storage.value = api.value
        let store = AccountStore(api: api, storage: storage, checksAppleCredential: false)
        await store.restore()
        let success = await store.updateProfile(nickname: "小粥", avatar: "leaf", accountID: "test-account")
        #expect(success)
        #expect(store.account?.displayName == "小粥")
        #expect(storage.value?.account.avatar == "leaf")
        let restored = AccountStore(api: api, storage: storage, checksAppleCredential: false)
        await restored.restore()
        #expect(restored.account?.displayName == "小粥")
        #expect(restored.account?.avatar == "leaf")
    }

    @Test func profileFailureKeepsOldIdentityAndWrongAccountCannotSave() async {
        let api = AccountStub()
        let storage = MemorySession()
        storage.value = api.value
        let store = AccountStore(api: api, storage: storage, checksAppleCredential: false)
        await store.restore()
        #expect(await store.updateProfile(nickname: "别人", avatar: "leaf", accountID: "other") == false)
        await api.setFailure(true)
        #expect(await store.updateProfile(nickname: "小粥", avatar: "leaf", accountID: "test-account") == false)
        #expect(store.account?.displayName == "粥记用户")
        #expect(storage.value?.account.nickname == nil)
    }

    @Test func remoteProfileSaveWithCacheFailureIsReportedTruthfully() async {
        let api = AccountStub()
        let storage = MemorySession()
        storage.value = api.value
        let store = AccountStore(api: api, storage: storage, checksAppleCredential: false)
        await store.restore()
        storage.failsSave = true
        #expect(await store.updateProfile(nickname: "小粥", avatar: "moon", accountID: "test-account"))
        #expect(store.account?.displayName == "小粥")
        #expect(store.message?.contains("资料已保存") == true)
    }

    @Test func oldAccountCacheWithoutProfileFieldsStillDecodes() throws {
        let data = Data(#"{"id":"old-account","provider":"apple"}"#.utf8)
        let account = try JSONDecoder().decode(AppAccount.self, from: data)
        #expect(account.displayName == "粥记用户")
        #expect(account.avatar == nil)
    }

    @Test func unreadableKeychainDoesNotClaimAnUnverifiedAccountExists() async {
        let storage = MemorySession()
        storage.failsRead = true
        let store = AccountStore(api: AccountStub(), storage: storage, checksAppleCredential: false)
        await store.restore()
        #expect(store.account == nil)
        #expect(store.message == AccountError.keychain.localizedDescription)
    }

    @Test func loginSurvivesRestoreAndLogoutClearsCredentials() async {
        let api = AccountStub()
        let storage = MemorySession()
        let store = AccountStore(api: api, storage: storage, checksAppleCredential: false)
        await store.finishLogin(challenge: "c", code: "code", identityToken: "token", appleUser: "apple-user")
        #expect(store.account?.id == "test-account")
        #expect(storage.value?.appleUser == "apple-user")
        let restored = AccountStore(api: api, storage: storage, checksAppleCredential: false)
        await restored.restore()
        #expect(restored.account == store.account)
        await restored.logout()
        #expect(restored.account == nil)
        #expect(storage.value == nil)
        #expect(await api.logoutCalls == 1)
    }

    @Test func keychainFailureDoesNotClaimSuccessfulLoginAndRevokesNewSession() async {
        let api = AccountStub()
        let storage = MemorySession()
        storage.failsSave = true
        let store = AccountStore(api: api, storage: storage, checksAppleCredential: false)
        await store.finishLogin(challenge: "c", code: "code", identityToken: "token", appleUser: "u")
        #expect(store.account == nil)
        #expect(storage.value == nil)
        #expect(store.message == AccountError.keychain.localizedDescription)
        #expect(await api.logoutCalls == 1)
    }

    @Test func offlineRestoreKeepsCachedIdentityButExpiredSessionClearsIt() async {
        let api = AccountStub()
        let storage = MemorySession()
        storage.value = api.value
        await api.setFailure(true)
        let store = AccountStore(api: api, storage: storage, checksAppleCredential: false)
        await store.restore()
        #expect(store.account != nil)
        #expect(store.message?.contains("暂未验证") == true)
        await api.setExpired()
        await store.restore()
        #expect(store.account == nil)
        #expect(storage.value == nil)
    }

    @Test func failedLogoutAndDeletionKeepSessionForRetry() async {
        let api = AccountStub()
        let storage = MemorySession()
        storage.value = api.value
        let store = AccountStore(api: api, storage: storage, checksAppleCredential: false)
        await store.restore()
        await api.setFailure(true)
        await store.logout()
        #expect(store.account != nil && storage.value != nil)
        await store.deleteAccount()
        #expect(store.account != nil && storage.value != nil)
        await api.setFailure(false)
        await store.deleteAccount()
        #expect(store.account == nil && storage.value == nil)
    }

    @Test func credentialRevocationClearsLocalSessionEvenOffline() async {
        let api = AccountStub()
        let storage = MemorySession()
        storage.value = api.value
        let store = AccountStore(api: api, storage: storage, checksAppleCredential: false)
        await store.restore()
        await api.setFailure(true)
        await store.credentialRevoked()
        #expect(store.account == nil && storage.value == nil)
    }

    @Test func guestChallengeFailureIsRecoverable() async {
        let api = AccountStub()
        let store = AccountStore(api: api, storage: MemorySession(), checksAppleCredential: false)
        await api.setFailure(true)
        await store.prepare()
        #expect(store.account == nil && store.challenge == nil && !store.isPreparing)
        await api.setFailure(false)
        await store.prepare()
        #expect(store.challenge != nil)
    }
}

@MainActor private final class WeChatStub: WeChatAuthorizing {
    var failure: WeChatLoginError?
    var receivedState: String?
    var waits = false
    var pending: CheckedContinuation<String, Error>?
    func authorize(state: String) async throws -> String {
        receivedState = state
        if let failure { throw failure }
        if waits { return try await withCheckedThrowingContinuation { pending = $0 } }
        return "one-use-code"
    }
    func cancel() { pending?.resume(throwing: WeChatLoginError.cancelled); pending = nil }
    func handle(url: URL) {}
    func handle(activity: NSUserActivity) {}
}

@MainActor struct WeChatAccountTests {
    @Test func weChatLoginPersistsAndAppleRevocationDoesNotLogItOut() async {
        let api = AccountStub(), storage = MemorySession(), wechat = WeChatStub()
        let store = AccountStore(api: api, storage: storage, checksAppleCredential: false, weChat: wechat)
        await store.loginWeChat()
        #expect(wechat.receivedState == "test-challenge")
        #expect(store.account?.provider == "wechat")
        #expect(storage.value?.appleUser == nil)
        #expect(storage.value?.token == "wechat-token")
        await store.credentialRevoked()
        #expect(store.account?.provider == "wechat")
        let restored = AccountStore(api: api, storage: storage, checksAppleCredential: false, weChat: wechat)
        await restored.restore()
        #expect(restored.account?.id == "wechat-account")
        await restored.logout()
        #expect(storage.value == nil)
    }

    @Test func unavailableWeChatAndFailedKeychainNeverLeaveLoggedInAccount() async {
        let api = AccountStub(), storage = MemorySession(), wechat = WeChatStub()
        let store = AccountStore(api: api, storage: storage, weChat: wechat)
        wechat.failure = .notInstalled
        await store.loginWeChat()
        #expect(store.account == nil)
        #expect(store.message == WeChatLoginError.notInstalled.localizedDescription)
        #expect(!store.isBusy && !store.isWaitingForWeChat)
        wechat.failure = nil
        storage.failsSave = true
        await store.loginWeChat()
        #expect(store.account == nil && storage.value == nil)
        #expect(await api.logoutCalls == 1)
        #expect(store.message == AccountError.keychain.localizedDescription)
    }

    @Test func cancellingAuthorizationClearsBusyStateAndAllowsRetry() async {
        let api = AccountStub(), storage = MemorySession(), wechat = WeChatStub()
        wechat.waits = true
        let store = AccountStore(api: api, storage: storage, weChat: wechat)
        let task = Task { await store.loginWeChat() }
        while wechat.pending == nil { await Task.yield() }
        #expect(store.isWaitingForWeChat)
        store.cancelWeChat()
        await task.value
        #expect(!store.isBusy && !store.isWaitingForWeChat)
        #expect(store.account == nil)
        wechat.waits = false
        await store.loginWeChat()
        #expect(store.account?.provider == "wechat")
    }
}
