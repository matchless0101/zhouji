import AuthenticationServices
import Foundation
import Observation

@MainActor @Observable
final class AccountStore {
    private(set) var account: AppAccount?
    private(set) var challenge: LoginChallenge?
    private(set) var isBusy = false
    private(set) var isPreparing = false
    private(set) var isWaitingForWeChat = false
    private let weChat: any WeChatAuthorizing
    var message: String?
    private var session: AccountSession?
    private let api: any AccountServing
    private let storage: any AccountSessionStoring
    private let checksAppleCredential: Bool

    init(api: any AccountServing = AccountAPI(), storage: any AccountSessionStoring = AccountKeychain(),
         checksAppleCredential: Bool = true, weChat: any WeChatAuthorizing = WeChatLogin()) {
        self.weChat = weChat
        self.api = api
        self.storage = storage
        self.checksAppleCredential = checksAppleCredential
    }

    func restore() async {
        guard !isBusy else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            guard let saved = try storage.read() else { return }
            guard saved.expiresAt > Date.now.timeIntervalSince1970 else {
                try clearSession()
                message = AccountError.expired.localizedDescription
                return
            }
            session = saved
            account = saved.account
            if checksAppleCredential, saved.account.provider == "apple", let user = saved.appleUser {
                let state = try await ASAuthorizationAppleIDProvider().credentialState(forUserID: user)
                if state == .revoked || state == .notFound || state == .transferred {
                    try? await api.logout(token: saved.token)
                    try clearSession()
                    message = AccountError.expired.localizedDescription
                    return
                }
            }
            let refreshed = try await api.account(token: saved.token)
            try applyAccount(refreshed)
            message = nil
        } catch AccountError.expired {
            do { try clearSession() } catch { message = AccountError.keychain.localizedDescription; return }
            message = AccountError.expired.localizedDescription
        } catch AccountError.keychain {
            message = AccountError.keychain.localizedDescription
        } catch {
            // Offline use remains available. Cached account status never implies sync success.
            message = account == nil ? AccountError.keychain.localizedDescription
                : "登录状态暂未验证，数据仍保存在本机。"
        }
    }

    func prepare() async {
        guard !isBusy, !isPreparing, account == nil else { return }
        isPreparing = true
        defer { isPreparing = false }
        do {
            let prepared = try await api.challenge()
            guard !isBusy, account == nil else { return }
            challenge = prepared
        } catch {
            guard !isBusy, account == nil else { return }
            challenge = nil
            message = error.localizedDescription
        }
    }

    func configure(_ request: ASAuthorizationAppleIDRequest) {
        guard let challenge, challenge.expiresAt > Date.now.timeIntervalSince1970 else {
            self.challenge = nil
            message = "登录请求已过期，请重试。"
            return
        }
        isBusy = true
        message = nil
        request.nonce = challenge.nonce
        request.state = challenge.challenge
        // No name or email is needed for a minimal task account.
        request.requestedScopes = []
    }

    func complete(_ result: Result<ASAuthorization, Error>) async {
        defer { isBusy = false; challenge = nil }
        switch result {
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let pending = challenge, credential.state == pending.challenge,
                  let codeData = credential.authorizationCode, let tokenData = credential.identityToken,
                  let code = String(data: codeData, encoding: .utf8),
                  let token = String(data: tokenData, encoding: .utf8) else {
                message = AccountError.invalidAuthorization.localizedDescription
                return
            }
            await finishLogin(challenge: pending.challenge, code: code, identityToken: token, appleUser: credential.user)
        case .failure(let error):
            if (error as? ASAuthorizationError)?.code != .canceled {
                message = AccountError.invalidAuthorization.localizedDescription
            }
        }
    }

    // Kept separate from the system authorization object so failure paths can be tested.
    func finishLogin(challenge: String, code: String, identityToken: String, appleUser: String) async {
        do {
            var result = try await api.login(challenge: challenge, code: code, identityToken: identityToken)
            result.appleUser = appleUser
            do { try storage.save(result) }
            catch {
                try? await api.logout(token: result.token)
                throw AccountError.keychain
            }
            session = result
            account = result.account
            message = nil
        } catch { message = error.localizedDescription }
    }

    func loginWeChat() async {
        guard !isBusy, account == nil else { return }
        isBusy = true
        message = nil
        defer { isBusy = false; isWaitingForWeChat = false }
        do {
            let pending = try await api.weChatChallenge()
            guard pending.expiresAt > Date.now.timeIntervalSince1970 else { throw WeChatLoginError.expired }
            isWaitingForWeChat = true
            let code = try await weChat.authorize(state: pending.challenge)
            isWaitingForWeChat = false
            var result = try await api.loginWeChat(challenge: pending.challenge, code: code)
            result.appleUser = nil
            guard result.account.provider == "wechat" else { throw AccountError.invalidResponse }
            do { try storage.save(result) }
            catch {
                try? await api.logout(token: result.token)
                throw AccountError.keychain
            }
            session = result
            account = result.account
            challenge = nil
        } catch { message = error.localizedDescription }
    }

    func weChatEnteredBackground() { weChat.applicationDidEnterBackground() }
    func weChatBecameActive() { weChat.applicationDidBecomeActive() }
    func cancelWeChat() { if isWaitingForWeChat { weChat.cancel() } }
    func handleWeChat(url: URL) { weChat.handle(url: url) }
    func handleWeChat(activity: NSUserActivity) { weChat.handle(activity: activity) }

    func logout() async {
        guard !isBusy, let session else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            try await api.logout(token: session.token)
            try clearSession()
            message = nil
        } catch { message = error.localizedDescription }
    }

    func updateProfile(nickname: String, avatar: String, accountID: String) async -> Bool {
        guard !isBusy, let session, session.account.id == accountID else { return false }
        isBusy = true
        message = nil
        defer { isBusy = false }
        do {
            let updated = try await api.updateProfile(token: session.token, nickname: nickname, avatar: avatar)
            guard updated.id == session.account.id else { throw AccountError.invalidResponse }
            do { try applyAccount(updated) }
            catch {
                // The server has saved the change; do not falsely present it as a failed save.
                message = "资料已保存，本机缓存暂未更新，请解锁设备后重新打开 App。"
            }
            return true
        } catch AccountError.expired {
            do { try clearSession() } catch { message = AccountError.keychain.localizedDescription; return false }
            message = AccountError.expired.localizedDescription
            return false
        } catch {
            message = error.localizedDescription
            return false
        }
    }

    private func applyAccount(_ updated: AppAccount) throws {
        guard var saved = session, saved.account.id == updated.id else { throw AccountError.invalidResponse }
        saved.account = updated
        session = saved
        account = updated
        try storage.save(saved)
    }

    func deleteAccount() async {
        guard !isBusy, let session else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            try await api.delete(token: session.token)
            try clearSession()
            message = "账户已注销，本机任务与计时记录已保留。"
        } catch AccountError.expired {
            try? clearSession()
            message = AccountError.expired.localizedDescription
        } catch { message = error.localizedDescription }
    }

    func credentialRevoked() async {
        guard !isBusy, session?.account.provider == "apple" else { return }
        isBusy = true
        defer { isBusy = false }
        if let session { try? await api.logout(token: session.token) }
        do { try clearSession(); message = AccountError.expired.localizedDescription }
        catch { message = AccountError.keychain.localizedDescription }
    }

    private func clearSession() throws {
        try storage.clear()
        session = nil
        account = nil
        challenge = nil
    }
}
