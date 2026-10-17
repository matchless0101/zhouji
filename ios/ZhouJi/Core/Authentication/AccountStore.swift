import AuthenticationServices
import Foundation
import Observation

@MainActor @Observable
final class AccountStore {
    private(set) var account: AppAccount?
    private(set) var challenge: LoginChallenge?
    private(set) var isBusy = false
    private(set) var isChangingLibrary = false
    private let libraries: LocalLibraryStore?
    private(set) var isPreparing = false
    private(set) var isWaitingForWeChat = false
    private(set) var weChatAvailability: WeChatAvailability
    private(set) var registrationRecovery: RecoveryMaterial?
    private let weChat: any WeChatAuthorizing
    var message: String?
    private var session: AccountSession?
    /// Bearer token for content sync; nil when signed out.
    var syncToken: String? { session?.token }
    private let api: any AccountServing
    private let storage: any AccountSessionStoring
    private let checksAppleCredential: Bool
    @ObservationIgnored private var isRefreshing = false
    @ObservationIgnored private var sessionRevision = 0
    @ObservationIgnored private var invalidatedSessionToken: String?

    init(api: any AccountServing = AccountAPI(), storage: any AccountSessionStoring = AccountKeychain(),
         checksAppleCredential: Bool = true, weChat: any WeChatAuthorizing = WeChatLogin(),
         libraries: LocalLibraryStore? = nil) {
        self.libraries = libraries
        self.weChat = weChat
        self.weChatAvailability = weChat.availability
        self.api = api
        self.storage = storage
        self.checksAppleCredential = checksAppleCredential
    }

    func restore() async {
        guard !isBusy, !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        let revision = sessionRevision
        do {
            guard let saved = try session ?? storage.read() else { return }
            if saved.token == invalidatedSessionToken {
                try clearSession()
                message = AccountError.expired.localizedDescription
                return
            }
            guard saved.expiresAt > Date.now.timeIntervalSince1970 else {
                try clearSession()
                message = AccountError.expired.localizedDescription
                return
            }
            try libraries?.restoreAuthentication(accountID: saved.account.id)
            session = saved
            account = saved.account
            if checksAppleCredential, saved.account.provider == "apple", let user = saved.appleUser {
                let state = try await ASAuthorizationAppleIDProvider().credentialState(forUserID: user)
                guard revision == sessionRevision else { return }
                if state == .revoked || state == .notFound || state == .transferred {
                    await credentialRevoked()
                    return
                }
            }
            let refreshed = try await api.account(token: saved.token)
            guard revision == sessionRevision else { return }
            try applyAccount(refreshed)
            message = nil
        } catch AccountError.expired {
            guard revision == sessionRevision else { return }
            do { try clearSession() } catch { message = AccountError.keychain.localizedDescription; return }
            message = AccountError.expired.localizedDescription
        } catch let error as LibraryError {
            guard revision == sessionRevision else { return }
            message = error.localizedDescription
        } catch AccountError.keychain {
            guard revision == sessionRevision else { return }
            message = AccountError.keychain.localizedDescription
        } catch {
            guard revision == sessionRevision else { return }
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
        sessionRevision += 1
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
        sessionRevision += 1
        let revision = sessionRevision
        isChangingLibrary = true
        defer { isChangingLibrary = false }
        do {
            var result = try await api.login(challenge: challenge, code: code, identityToken: identityToken)
            guard revision == sessionRevision else {
                try? await api.logout(token: result.token)
                return
            }
            result.appleUser = appleUser
            try await persistLogin(result)
            message = nil
        } catch {
            if revision == sessionRevision { message = error.localizedDescription }
        }
    }

    func loginWeChat() async {
        guard !isBusy, account == nil else { return }
        refreshWeChatAvailability()
        guard weChatAvailability == .available else { message = weChatAvailability.loginMessage; return }
        isBusy = true
        sessionRevision += 1
        let revision = sessionRevision
        message = nil
        defer { isBusy = false; isWaitingForWeChat = false; isChangingLibrary = false }
        do {
            let pending = try await api.weChatChallenge()
            guard pending.expiresAt > Date.now.timeIntervalSince1970 else { throw WeChatLoginError.expired }
            isWaitingForWeChat = true
            let code = try await weChat.authorize(state: pending.challenge)
            isWaitingForWeChat = false
            isChangingLibrary = true
            var result = try await api.loginWeChat(challenge: pending.challenge, code: code)
            guard revision == sessionRevision else {
                try? await api.logout(token: result.token)
                return
            }
            result.appleUser = nil
            guard result.account.provider == "wechat" else { throw AccountError.invalidResponse }
            try await persistLogin(result)
            challenge = nil
        } catch {
            if revision == sessionRevision { message = error.localizedDescription }
        }
    }

    private func persistLogin(_ result: AccountSession) async throws {
        let prepared: LocalLibrary?
        do {
            prepared = try libraries?.prepareLogin(accountID: result.account.id)
            try storage.save(result)
        } catch {
            try? await api.logout(token: result.token)
            throw error
        }
        if let prepared { libraries?.completeLogin(accountID: result.account.id, prepared: prepared) }
        session = result
        account = result.account
    }

    func weChatEnteredBackground() { weChat.applicationDidEnterBackground() }
    func refreshWeChatAvailability() { weChatAvailability = weChat.availability }
    func weChatBecameActive() { refreshWeChatAvailability(); weChat.applicationDidBecomeActive() }
    func cancelWeChat() { if isWaitingForWeChat { weChat.cancel() } }
    func handleWeChat(url: URL) { weChat.handle(url: url) }
    func handleWeChat(activity: NSUserActivity) { weChat.handle(activity: activity) }

    func logout() async {
        guard !isBusy, let session else { return }
        isBusy = true
        sessionRevision += 1
        let revision = sessionRevision
        defer { isBusy = false }
        isChangingLibrary = true
        defer { isChangingLibrary = false }
        do {
            let prepared = try libraries?.prepareLogout()
            try await api.logout(token: session.token)
            guard revision == sessionRevision else { return }
            try clearSession()
            if let prepared { libraries?.completeLogout(prepared: prepared) }
            message = nil
        } catch {
            if revision == sessionRevision { message = error.localizedDescription }
        }
    }

    func updateProfile(nickname: String, avatar: String, accountID: String) async -> Bool {
        guard !isBusy, let session, session.account.id == accountID else { return false }
        let nickname = ProfileNickname.normalize(nickname)
        guard ProfileNickname.isValid(nickname) else {
            message = AccountError.invalidProfile.localizedDescription
            return false
        }
        isBusy = true
        sessionRevision += 1
        let revision = sessionRevision
        message = nil
        defer { isBusy = false }
        do {
            let updated = try await api.updateProfile(token: session.token, nickname: nickname, avatar: avatar)
            guard revision == sessionRevision else { return false }
            guard updated.id == session.account.id else { throw AccountError.invalidResponse }
            do { try applyAccount(updated) }
            catch {
                // The server has saved the change; do not falsely present it as a failed save.
                message = "资料已保存，本机缓存暂未更新，请解锁设备后重新打开 App。"
            }
            return true
        } catch AccountError.expired {
            guard revision == sessionRevision else { return false }
            do { try clearSession() } catch { message = AccountError.keychain.localizedDescription; return false }
            message = AccountError.expired.localizedDescription
            return false
        } catch {
            guard revision == sessionRevision else { return false }
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
        sessionRevision += 1
        let revision = sessionRevision
        defer { isBusy = false }
        isChangingLibrary = true
        defer { isChangingLibrary = false }
        do {
            let prepared = try libraries?.prepareLogout()
            let backup = try libraries?.prepareDeletionBackup()
            try await api.delete(token: session.token)
            // Retain the export even if clearing the Keychain subsequently fails.
            libraries?.retainDeletedBackup(backup)
            guard revision == sessionRevision else { return }
            try clearSession()
            if let prepared { libraries?.completeLogout(prepared: prepared) }
            message = libraries == nil ? "账户已注销，本机任务与计时记录已保留。"
                : "账户已注销，已返回游客记录。注销前内容副本保存在本机。"
        } catch AccountError.expired {
            guard revision == sessionRevision else { return }
            do { try clearSession() } catch { message = AccountError.keychain.localizedDescription; return }
            message = AccountError.expired.localizedDescription
        } catch {
            if revision == sessionRevision { message = error.localizedDescription }
        }
    }

    func credentialRevoked() async {
        guard let revoked = session, revoked.account.provider == "apple" else { return }
        sessionRevision += 1
        // Never reload revoked credentials if the Keychain is temporarily locked.
        invalidatedSessionToken = revoked.token
        do { try clearSession(); message = AccountError.expired.localizedDescription }
        catch {
            forgetSession()
            message = AccountError.keychain.localizedDescription
        }
        // Local authorization ends immediately, even when the logout service is offline or slow.
        try? await api.logout(token: revoked.token)
    }

    private func clearSession() throws {
        try storage.clear()
        sessionRevision += 1
        forgetSession()
    }

    private func forgetSession() {
        session = nil
        account = nil
        libraries?.authenticationExpired()
        challenge = nil
        registrationRecovery = nil
    }
}

// Same-file extensions retain private credential access without exposing tokens to views.
extension AccountStore {
    func finishSavingRegistrationRecovery() { registrationRecovery = nil }
    private func beginCredentialOperation() -> Int? {
        guard !isBusy else { return nil }
        isBusy = true
        sessionRevision += 1
        message = nil
        return sessionRevision
    }

    private func endCredentialOperation(_ revision: Int) {
        guard sessionRevision == revision else { return }
        isBusy = false
        isWaitingForWeChat = false
        isChangingLibrary = false
    }

    func cancelCredentialOperation() {
        sessionRevision += 1
        weChat.cancel()
        isBusy = false
        isWaitingForWeChat = false
        isChangingLibrary = false
    }

    private func credentialOperationFailed(_ error: Error, revision: Int) {
        guard sessionRevision == revision else { return }
        if (error as? AccountError) == .expired {
            invalidatedSessionToken = session?.token
            try? clearSession()
            forgetSession()
            isBusy = false
            isWaitingForWeChat = false
            isChangingLibrary = false
        }
        message = error.localizedDescription
    }

    func loginPassword(username: String, password: String) async -> Bool {
        guard account == nil, PasswordCredentials.isValidUsername(username),
              PasswordCredentials.isValidPassword(password) else { message = AccountError.invalidInput.localizedDescription; return false }
        guard let revision = beginCredentialOperation() else { return false }
        defer { endCredentialOperation(revision) }
        do {
            var result = try await api.loginPassword(username: PasswordCredentials.normalizedUsername(username), password: password)
            guard revision == sessionRevision else { try? await api.logout(token: result.token); return false }
            guard result.account.provider == "password", result.account.hasPassword else { throw AccountError.invalidResponse }
            result.appleUser = nil
            isChangingLibrary = true
            try await persistLogin(result)
            challenge = nil
            return true
        } catch {
            credentialOperationFailed(error, revision: revision)
            return false
        }
    }

    func registerPassword(username: String, password: String) async -> RecoveryMaterial? {
        guard account == nil, PasswordCredentials.isValidUsername(username),
              PasswordCredentials.isValidPassword(password) else { message = AccountError.invalidInput.localizedDescription; return nil }
        guard let revision = beginCredentialOperation() else { return nil }
        defer { endCredentialOperation(revision) }
        var created = false
        do {
            var result = try await api.registerPassword(username: PasswordCredentials.normalizedUsername(username), password: password)
            created = true
            guard revision == sessionRevision else { try? await api.logout(token: result.session.token); return nil }
            guard result.session.account.provider == "password", result.session.account.hasPassword,
                  let username = result.session.account.username,
                  PasswordCredentials.isValidRecoveryCode(result.recoveryCode) else { throw AccountError.invalidResponse }
            result.session.appleUser = nil
            isChangingLibrary = true
            try await persistLogin(result.session)
            challenge = nil
            let material = RecoveryMaterial(username: username, code: result.recoveryCode)
            registrationRecovery = material
            return material
        } catch {
            guard revision == sessionRevision else { return nil }
            if created || (error as? AccountError) == .unavailable {
                message = "账户可能已创建。请尝试用刚设置的用户名密码登录，登录后可重新生成恢复码。\n" + error.localizedDescription
            } else {
                message = error.localizedDescription
            }
            return nil
        }
    }

    func recoverPassword(username: String, recoveryCode: String, newPassword: String) async -> RecoveryMaterial? {
        guard account == nil, PasswordCredentials.isValidUsername(username),
              PasswordCredentials.isValidRecoveryCode(recoveryCode), PasswordCredentials.isValidPassword(newPassword)
        else { message = AccountError.invalidInput.localizedDescription; return nil }
        guard let revision = beginCredentialOperation() else { return nil }
        defer { endCredentialOperation(revision) }
        do {
            let result = try await api.recoverPassword(username: PasswordCredentials.normalizedUsername(username),
                recoveryCode: recoveryCode, newPassword: newPassword)
            guard revision == sessionRevision else { return nil }
            guard PasswordCredentials.isValidRecoveryCode(result.code) else { throw AccountError.invalidResponse }
            return result
        } catch {
            guard revision == sessionRevision else { return nil }
            message = (error as? AccountError) == .unavailable
                ? "未能确认重置结果。请尝试用新密码登录，登录后可重新生成恢复码。"
                : error.localizedDescription
            return nil
        }
    }

    private func replaceCredentialSession(_ result: AccountSession) async throws {
        guard let previous = session, result.account.id == previous.account.id else { throw AccountError.invalidResponse }
        do {
            try storage.save(result)
        } catch {
            invalidatedSessionToken = previous.token
            try? storage.clear()
            sessionRevision += 1
            forgetSession()
            isBusy = false
            isWaitingForWeChat = false
            try? await api.logout(token: result.token)
            message = "账户凭据已更新，需重新登录。" + AccountError.keychain.localizedDescription
            throw AccountError.keychain
        }
        session = result
        account = result.account
    }

    func changePassword(password: String, newPassword: String) async -> Bool {
        guard let current = session, current.account.hasPassword,
              PasswordCredentials.isValidPassword(password), PasswordCredentials.isValidPassword(newPassword)
        else { message = AccountError.invalidInput.localizedDescription; return false }
        guard let revision = beginCredentialOperation() else { return false }
        defer { endCredentialOperation(revision) }
        do {
            let result = try await api.changePassword(token: current.token, password: password, newPassword: newPassword)
            guard revision == sessionRevision else { try? await api.logout(token: result.token); return false }
            try await replaceCredentialSession(result)
            message = "密码已修改，其他设备需重新登录。"
            return true
        } catch { credentialOperationFailed(error, revision: revision); return false }
    }

    func rotateRecoveryCode(password: String) async -> RecoveryMaterial? {
        guard let current = session, current.account.hasPassword, PasswordCredentials.isValidPassword(password)
        else { message = AccountError.invalidInput.localizedDescription; return nil }
        guard let revision = beginCredentialOperation() else { return nil }
        defer { endCredentialOperation(revision) }
        do {
            let result = try await api.rotateRecoveryCode(token: current.token, password: password)
            guard revision == sessionRevision else { try? await api.logout(token: result.session.token); return nil }
            guard let username = result.session.account.username,
                  PasswordCredentials.isValidRecoveryCode(result.recoveryCode) else { throw AccountError.invalidResponse }
            try await replaceCredentialSession(result.session)
            return RecoveryMaterial(username: username, code: result.recoveryCode)
        } catch { credentialOperationFailed(error, revision: revision); return nil }
    }

    func bindWeChat(password: String) async -> Bool {
        guard let current = session, current.account.hasPassword, PasswordCredentials.isValidPassword(password)
        else { message = AccountError.invalidInput.localizedDescription; return false }
        refreshWeChatAvailability()
        guard weChatAvailability == .available else {
            message = weChatAvailability == .notInstalled
                ? "当前设备未安装微信，暂时无法绑定；账号密码登录不受影响。"
                : weChatAvailability.loginMessage
            return false
        }
        guard let revision = beginCredentialOperation() else { return false }
        defer { endCredentialOperation(revision) }
        do {
            let pending = try await api.weChatBindingChallenge(token: current.token, password: password)
            guard revision == sessionRevision else { return false }
            guard pending.expiresAt > Date.now.timeIntervalSince1970 else { throw AccountError.bindingExpired }
            isWaitingForWeChat = true
            let code = try await weChat.authorize(state: pending.challenge)
            guard revision == sessionRevision else { return false }
            isWaitingForWeChat = false
            let updated = try await api.bindWeChat(token: current.token, challenge: pending.challenge, code: code)
            guard revision == sessionRevision else { return false }
            guard updated.id == current.account.id else { throw AccountError.invalidResponse }
            try applyAccount(updated)
            message = "微信已绑定，可使用微信或用户名密码登录此账户。"
            return true
        } catch {
            return await reconcileWeChatIfUncertain(error, expectedBound: true, token: current.token, revision: revision)
        }
    }

    func unbindWeChat(password: String) async -> Bool {
        guard let current = session, current.account.hasPassword, PasswordCredentials.isValidPassword(password)
        else { message = AccountError.invalidInput.localizedDescription; return false }
        guard let revision = beginCredentialOperation() else { return false }
        defer { endCredentialOperation(revision) }
        do {
            let result = try await api.unbindWeChat(token: current.token, password: password)
            guard revision == sessionRevision else {
                if let replacement = result.session { try? await api.logout(token: replacement.token) }
                return false
            }
            guard result.account.id == current.account.id else { throw AccountError.invalidResponse }
            if let replacement = result.session { try await replaceCredentialSession(replacement) }
            else { try applyAccount(result.account) }
            message = "微信已解绑，任务记录保留。微信中的应用授权可在微信设置中管理。"
            return true
        } catch {
            return await reconcileWeChatIfUncertain(error, expectedBound: false, token: current.token, revision: revision)
        }
    }

    private func reconcileWeChatIfUncertain(_ error: Error, expectedBound: Bool, token: String, revision: Int) async -> Bool {
        guard revision == sessionRevision else { return false }
        guard (error as? AccountError) == .unavailable || (error as? AccountError) == .invalidResponse || error is URLError else {
            credentialOperationFailed(error, revision: revision)
            return false
        }
        do {
            let updated = try await api.account(token: token)
            guard revision == sessionRevision else { return false }
            try applyAccount(updated)
            if updated.weChatBound == expectedBound {
                message = expectedBound ? "已核实微信绑定成功。" : "已核实微信已解绑，任务记录保留。"
                return true
            }
            message = "未能完成微信授权变更，已核实当前绑定状态，请重试。"
        } catch {
            credentialOperationFailed(error, revision: revision)
            if revision == sessionRevision {
                message = account == nil
                    ? "登录凭据已更新，请使用账号密码重新登录，核实微信绑定状态。"
                    : "暂时无法核实微信绑定状态，请联网后重试。"
            }
        }
        return false
    }
}
