import Foundation
import SwiftData
import Testing
@testable import ZhouJi

@MainActor struct PasswordAuthenticationTests {
    @Test func oldKeychainDecodesNewCapabilities() throws {
        let value = try JSONDecoder().decode(AppAccount.self, from: Data(#"{"id":"old","provider":"apple"}"#.utf8))
        #expect(!value.hasPassword)
        #expect(!value.weChatBound)
        #expect(value.username == nil)
        #expect(AppAccount(id: "unknown", provider: "future").providerName != "Apple 登录")
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let bound = try decoder.decode(AppAccount.self, from: Data(#"{"id":"bound","provider":"wechat","has_password":true,"wechat_bound":true,"username":"alice"}"#.utf8))
        #expect(bound.hasPassword && bound.weChatBound && bound.username == "alice")
    }

    @Test func credentialBoundariesMatchServer() {
        #expect(PasswordCredentials.normalizedUsername(" Alice_1 ") == "alice_1")
        #expect(PasswordCredentials.isValidUsername(" Alice_1 "))
        #expect(PasswordCredentials.isValidUsername("\u{001C}Alice_1\u{001F}"))
        #expect(PasswordCredentials.normalizedUsername("\u{001C}Alice_1\u{001F}") == "alice_1")
        #expect(!PasswordCredentials.isValidUsername("\u{200B}alice\u{200B}"))
        for value in ["abc", String(repeating: "a", count: 33), "你好用户", "a-bc", "Kate"] {
            #expect(!PasswordCredentials.isValidUsername(value))
        }
        #expect(PasswordCredentials.isValidPassword(String(repeating: "中", count: 128)))
        #expect(!PasswordCredentials.isValidPassword(String(repeating: "a", count: 14)))
        #expect(PasswordCredentials.isValidRecoveryCode("abcd-efgh-ijkl-mnop-qrst-uvwx-yz23-4567"))
        #expect(!PasswordCredentials.isValidRecoveryCode(String(repeating: "ß", count: 16)))
    }

    @Test func invalidLoginResponseIsNotExpiredSession() {
        let body = Data(#"{"detail":{"code":"invalid_credentials","message":"wrong"}}"#.utf8)
        #expect(AccountAPI.responseError(status: 401, path: "auth/password/login", data: body) == .invalidCredentials)
        #expect(AccountAPI.responseError(status: 401, path: "account", data: Data()) == .expired)
    }

    @Test func registrationReturnsRecoveryMaterialButNeverPersistsIt() async throws {
        let api = PasswordAccountStub(), storage = PasswordMemorySession()
        let store = AccountStore(api: api, storage: storage, checksAppleCredential: false)
        let recovery = await store.registerPassword(username: "alice", password: "a safe initial password")
        #expect(recovery?.username == "alice")
        #expect(recovery?.code == "ABCD-EFGH-IJKL-MNOP-QRST-UVWX-YZ23-4567")
        #expect(store.account?.hasPassword == true)
        #expect(store.registrationRecovery?.code == recovery?.code)
        let saved = try JSONEncoder().encode(#require(storage.value))
        #expect(!String(decoding: saved, as: UTF8.self).contains("ABCD-EFGH"))
        store.finishSavingRegistrationRecovery()
        #expect(store.registrationRecovery == nil)
    }

    @Test func failedKeychainSaveDoesNotPretendRegistrationWasRolledBack() async {
        let api = PasswordAccountStub(), storage = PasswordMemorySession()
        storage.failsSave = true
        let store = AccountStore(api: api, storage: storage, checksAppleCredential: false)
        let result = await store.registerPassword(username: "alice", password: "a safe initial password")
        #expect(result == nil)
        #expect(store.account == nil)
        #expect(store.message?.contains("账户可能已创建") == true)
        #expect(await api.revokedTokens == ["password-token"])
    }

    @Test func bindingAndWeChatSessionUnbindingKeepSameLibrary() async throws {
        let guest = try ModelContainer(for: Goal.self, TodoTask.self, TimingSession.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let libraries = try LocalLibraryStore(guest: guest, inMemory: true)
        let api = PasswordAccountStub(), storage = PasswordMemorySession()
        let store = AccountStore(api: api, storage: storage, checksAppleCredential: false,
            weChat: PasswordWeChatStub(), libraries: libraries)
        _ = await store.registerPassword(username: "alice", password: "a safe initial password")
        let original = libraries.current.container
        _ = try TaskService.create(title: "原来的任务", in: original.mainContext)
        #expect(await store.bindWeChat(password: "a safe initial password"))
        #expect(libraries.current.container === original)
        #expect(store.account?.weChatBound == true)
        await store.logout()
        await store.loginWeChat()
        #expect(store.account?.id == "password-account" && store.account?.provider == "wechat")
        let beforeUnbind = libraries.current.container
        #expect(await store.unbindWeChat(password: "a safe initial password"))
        #expect(libraries.current.container === beforeUnbind)
        #expect(store.account?.provider == "password" && store.account?.weChatBound == false)
        #expect(try beforeUnbind.mainContext.fetch(FetchDescriptor<TodoTask>()).map(\.title) == ["原来的任务"])
    }

    @Test func cancelledLoginCannotRestoreSessionAfterNewLogin() async throws {
        let api = PasswordAccountStub(), storage = PasswordMemorySession()
        let store = AccountStore(api: api, storage: storage, checksAppleCredential: false)
        await api.setDelaysLogin(true)
        let old = Task { await store.loginPassword(username: "alice", password: "a safe initial password") }
        let deadline = ContinuousClock.now + .seconds(5)
        while !(await api.isLoginWaiting) {
            try #require(ContinuousClock.now < deadline)
            await Task.yield()
        }
        store.cancelCredentialOperation()
        await api.setDelaysLogin(false)
        #expect(await store.loginPassword(username: "alice", password: "a safe initial password"))
        let current = try #require(storage.value?.token)
        await api.completeLogin()
        #expect(!(await old.value))
        #expect(storage.value?.token == current)
        #expect(await api.revokedTokens == ["password-token"])
        await store.credentialRevoked()
        #expect(store.account?.provider == "password")
    }

    @Test func missingWeChatPreventsBindingButDoesNotPreventPasswordSecurityOrUnbinding() async throws {
        let api = PasswordAccountStub(), storage = PasswordMemorySession(), weChat = PasswordWeChatStub()
        let store = AccountStore(api: api, storage: storage, checksAppleCredential: false, weChat: weChat)
        _ = await store.registerPassword(username: "alice", password: "a safe initial password")
        weChat.availability = .notInstalled
        #expect(!(await store.bindWeChat(password: "a safe initial password")))
        #expect(await api.bindingRequests == 0)
        weChat.availability = .available
        #expect(await store.bindWeChat(password: "a safe initial password"))
        await store.logout()
        await store.loginWeChat()
        #expect(store.account?.provider == "wechat" && store.account?.hasPassword == true)
        weChat.availability = .notInstalled
        #expect(await store.changePassword(password: "a safe initial password", newPassword: "a different safe password"))
        #expect(await store.rotateRecoveryCode(password: "a different safe password") != nil)
        #expect(await store.unbindWeChat(password: "a different safe password"))
        #expect(store.account?.id == "password-account" && store.account?.provider == "password")
    }

    @Test func bindingConflictAndAuthorizationCancellationKeepIdentityAndSession() async throws {
        let api = PasswordAccountStub(), storage = PasswordMemorySession(), weChat = PasswordWeChatStub()
        let store = AccountStore(api: api, storage: storage, checksAppleCredential: false, weChat: weChat)
        _ = await store.registerPassword(username: "alice", password: "a safe initial password")
        let original = try #require(storage.value)
        await api.setBindingFailure(.weChatInUse)
        #expect(!(await store.bindWeChat(password: "a safe initial password")))
        #expect(store.account?.id == original.account.id && store.account?.weChatBound == false)
        #expect(storage.value?.token == original.token && !store.isBusy)
        await api.setBindingFailure(nil)
        weChat.authorizationError = WeChatLoginError.cancelled
        #expect(!(await store.bindWeChat(password: "a safe initial password")))
        #expect(store.account?.weChatBound == false && !store.isBusy && !store.isWaitingForWeChat)
        #expect(storage.value?.token == original.token)
    }

    @Test func lostBindingAndUnbindingResponsesAreReconciledWithServer() async {
        let api = PasswordAccountStub(), storage = PasswordMemorySession()
        let store = AccountStore(api: api, storage: storage, checksAppleCredential: false, weChat: PasswordWeChatStub())
        _ = await store.registerPassword(username: "alice", password: "a safe initial password")
        await api.dropBindingResponses()
        #expect(await store.bindWeChat(password: "a safe initial password"))
        #expect(store.account?.weChatBound == true)
        #expect(await store.unbindWeChat(password: "a safe initial password"))
        #expect(store.account?.weChatBound == false && store.account?.id == "password-account")
    }

    @Test func lostWeChatUnbindingResponseDoesNotKeepRevokedSession() async {
        let api = PasswordAccountStub(), storage = PasswordMemorySession()
        let store = AccountStore(api: api, storage: storage, checksAppleCredential: false, weChat: PasswordWeChatStub())
        _ = await store.registerPassword(username: "alice", password: "a safe initial password")
        await store.logout(); await store.loginWeChat()
        await api.dropBindingResponses()
        #expect(!(await store.unbindWeChat(password: "a safe initial password")))
        #expect(store.account == nil && storage.value == nil)
        #expect(store.message?.contains("重新登录") == true)
    }

    @Test func replacementSaveFailureCannotReloadInvalidOldSession() async {
        let api = PasswordAccountStub(), storage = PasswordMemorySession()
        let store = AccountStore(api: api, storage: storage, checksAppleCredential: false)
        _ = await store.registerPassword(username: "alice", password: "a safe initial password")
        storage.failsSave = true
        storage.failsClear = true
        #expect(!(await store.changePassword(password: "a safe initial password", newPassword: "a different safe password")))
        #expect(store.account == nil && !store.isBusy)
        await store.restore()
        #expect(store.account == nil)
    }
}

@MainActor private final class PasswordMemorySession: AccountSessionStoring {
    var value: AccountSession?
    var failsSave = false
    var failsClear = false
    func read() throws -> AccountSession? { value }
    func save(_ value: AccountSession) throws {
        if failsSave { throw AccountError.keychain }
        self.value = value
    }
    func clear() throws {
        if failsClear { throw AccountError.keychain }
        value = nil
    }
}

private actor PasswordAccountStub: AccountServing {
    var revokedTokens: [String] = []
    var bindingRequests = 0
    private var bindingFailure: AccountError?
    func setBindingFailure(_ error: AccountError?) { bindingFailure = error }
    private var dropsBindingResponses = false
    private var expiredTokens: Set<String> = []
    func dropBindingResponses() { dropsBindingResponses = true }
    private var serial = 0
    private var delaysLogin = false
    private var pendingLogin: CheckedContinuation<AccountSession, Error>?
    private var pendingValue: AccountSession?
    var isLoginWaiting: Bool { pendingLogin != nil }
    func setDelaysLogin(_ value: Bool) { delaysLogin = value }
    func completeLogin() {
        if let pendingValue { pendingLogin?.resume(returning: pendingValue) }
        pendingLogin = nil; pendingValue = nil
    }
    private var profile = AppAccount(id: "password-account", provider: "password", hasPassword: true, username: "alice")
    private func value() -> AccountSession {
        serial += 1
        return AccountSession(token: serial == 1 ? "password-token" : "password-token-\(serial)",
            expiresAt: Date.now.timeIntervalSince1970 + 3600, account: profile)
    }
    func challenge() async throws -> LoginChallenge { throw AccountError.unavailable }
    func weChatChallenge() async throws -> LoginChallenge {
        LoginChallenge(challenge: "challenge", nonce: "nonce", expiresAt: Date.now.timeIntervalSince1970 + 300)
    }
    func loginWeChat(challenge: String, code: String) async throws -> AccountSession {
        profile = AppAccount(id: profile.id, provider: "wechat", hasPassword: true, weChatBound: true, username: "alice")
        return value()
    }
    func login(challenge: String, code: String, identityToken: String) async throws -> AccountSession { throw AccountError.unavailable }
    func account(token: String) async throws -> AppAccount {
        if expiredTokens.contains(token) { throw AccountError.expired }
        return profile
    }
    func updateProfile(token: String, nickname: String, avatar: String) async throws -> AppAccount { profile }
    func logout(token: String) async throws { revokedTokens.append(token) }
    func delete(token: String) async throws {}
    func registerPassword(username: String, password: String) async throws -> PasswordRegistration {
        PasswordRegistration(session: value(), recoveryCode: "ABCD-EFGH-IJKL-MNOP-QRST-UVWX-YZ23-4567")
    }
    func loginPassword(username: String, password: String) async throws -> AccountSession {
        let result = value()
        if delaysLogin {
            pendingValue = result
            return try await withCheckedThrowingContinuation { pendingLogin = $0 }
        }
        return result
    }
    func recoverPassword(username: String, recoveryCode: String, newPassword: String) async throws -> RecoveryMaterial {
        RecoveryMaterial(username: username, code: "ABCD-EFGH-IJKL-MNOP-QRST-UVWX-YZ23-4567")
    }
    func changePassword(token: String, password: String, newPassword: String) async throws -> AccountSession { value() }
    func rotateRecoveryCode(token: String, password: String) async throws -> RecoveryRotation {
        try await registerPassword(username: "alice", password: password)
    }
    func weChatBindingChallenge(token: String, password: String) async throws -> LoginChallenge {
        bindingRequests += 1
        return try await weChatChallenge()
    }
    func bindWeChat(token: String, challenge: String, code: String) async throws -> AppAccount {
        if let bindingFailure { throw bindingFailure }
        profile.weChatBound = true
        if dropsBindingResponses { throw AccountError.unavailable }
        return profile
    }
    func unbindWeChat(token: String, password: String) async throws -> BindingResult {
        let wasWeChat = profile.provider == "wechat"
        profile = AppAccount(id: profile.id, provider: "password", hasPassword: true, username: "alice")
        if dropsBindingResponses {
            if wasWeChat { expiredTokens.insert(token) }
            throw AccountError.unavailable
        }
        return BindingResult(account: profile, session: wasWeChat ? value() : nil)
    }
}

@MainActor private final class PasswordWeChatStub: WeChatAuthorizing {
    var availability: WeChatAvailability = .available
    var authorizationError: (any Error)?
    func authorize(state: String) async throws -> String {
        if let authorizationError { throw authorizationError }
        return "wx-code"
    }
    func cancel() {}
    func handle(url: URL) {}
    func handle(activity: NSUserActivity) {}
}
