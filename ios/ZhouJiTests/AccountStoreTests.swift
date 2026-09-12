import Foundation
import Testing
@testable import ZhouJi

private actor AccountStub: AccountServing {
    var fails = false
    var expired = false
    var logoutCalls = 0
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
    func account(token: String) async throws -> AppAccount {
        if expired { throw AccountError.expired }
        if fails { throw AccountError.unavailable }
        return value.account
    }
    func logout(token: String) async throws {
        logoutCalls += 1
        if fails { throw AccountError.unavailable }
    }
    func delete(token: String) async throws {
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
