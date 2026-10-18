#if DEBUG
import Foundation

/// Explicit in-memory UI test fixture. Release builds contain neither this service nor its entry point.
actor PasswordAuthenticationPreview: AccountServing {
    private struct User {
        var password: String
        var recoveryCode: String
        var nickname = "粥记用户"
        var avatar = "sunrise"
        var bound = false
        var hasPassword = true
        var accountID: String?
    }
    private var users: [String: User] = [:]
    private var sessions: [String: (username: String, method: String)] = [:]
    private var bindings: [String: String] = [:]
    private let initialCode = "ABCD-EFGH-IJKL-MNOP-QRST-UVWX-YZ23-4567"
    private let delaysLogin: Bool

    init(seedBoundAccount: Bool = false, delaysLogin: Bool = false, seedIndependentWeChat: Bool = false) {
        self.delaysLogin = delaysLogin
        if seedBoundAccount {
            users["sample_user"] = User(password: "ui-test-long-password", recoveryCode: initialCode, bound: true)
            sessions["preview-bound-session"] = (username: "sample_user", method: "wechat")
        }
        if seedIndependentWeChat {
            users["legacy_wechat"] = User(password: "", recoveryCode: "", bound: true, hasPassword: false,
                accountID: "preview-independent-wechat")
            sessions["preview-independent-session"] = (username: "legacy_wechat", method: "wechat")
        }
    }

    private func profile(_ username: String, method: String) throws -> AppAccount {
        guard let user = users[username] else { throw AccountError.expired }
        return AppAccount(id: user.accountID ?? "preview-password-\(username)", provider: method, nickname: user.nickname,
            avatar: user.avatar, hasPassword: user.hasPassword, weChatBound: user.bound,
            username: user.hasPassword ? username : nil)
    }
    private func issue(_ username: String, method: String = "password") throws -> AccountSession {
        let token = UUID().uuidString
        sessions[token] = (username, method)
        return AccountSession(token: token, expiresAt: Date.now.timeIntervalSince1970 + 3600,
            account: try profile(username, method: method))
    }
    private func userFor(_ token: String, password: String) throws -> String {
        guard let session = sessions[token] else { throw AccountError.expired }
        guard users[session.username]?.password == password else { throw AccountError.invalidCredentials }
        return session.username
    }
    private func revoke(_ username: String) { sessions = sessions.filter { $0.value.username != username } }
    private func freshCode() -> String {
        let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ234567")
        return (0..<8).map { _ in String((0..<4).map { _ in alphabet.randomElement()! }) }.joined(separator: "-")
    }
    func challenge() async throws -> LoginChallenge { throw AccountError.unavailable }
    func login(challenge: String, code: String, identityToken: String) async throws -> AccountSession { throw AccountError.unavailable }
    func weChatChallenge() async throws -> LoginChallenge {
        LoginChallenge(challenge: UUID().uuidString, nonce: "preview", expiresAt: Date.now.timeIntervalSince1970 + 300)
    }
    func loginWeChat(challenge: String, code: String) async throws -> AccountSession {
        guard let username = users.first(where: { $0.value.bound })?.key else { throw AccountError.unavailable }
        return try issue(username, method: "wechat")
    }
    func account(token: String) async throws -> AppAccount {
        guard let session = sessions[token] else { throw AccountError.expired }
        return try profile(session.username, method: session.method)
    }
    func updateProfile(token: String, nickname: String, avatar: String) async throws -> AppAccount {
        guard let session = sessions[token] else { throw AccountError.expired }
        users[session.username]?.nickname = nickname
        users[session.username]?.avatar = avatar
        return try profile(session.username, method: session.method)
    }
    func logout(token: String) async throws { sessions[token] = nil }
    func delete(token: String) async throws {
        guard let current = sessions[token] else { throw AccountError.expired }
        revoke(current.username); users[current.username] = nil
    }
    func registerPassword(username: String, password: String) async throws -> PasswordRegistration {
        guard users[username] == nil else { throw AccountError.usernameTaken }
        users[username] = User(password: password, recoveryCode: initialCode)
        return PasswordRegistration(session: try issue(username), recoveryCode: initialCode)
    }
    func setupPassword(token: String, username: String, password: String) async throws -> PasswordRegistration {
        guard let current = sessions[token], var user = users[current.username],
              current.method == "wechat", !user.hasPassword else { throw AccountError.passwordAlreadySet }
        guard users[username] == nil else { throw AccountError.usernameTaken }
        user.password = password; user.recoveryCode = initialCode; user.hasPassword = true
        user.accountID = user.accountID ?? "preview-password-\(current.username)"
        revoke(current.username); users[current.username] = nil; users[username] = user
        return PasswordRegistration(session: try issue(username, method: "wechat"), recoveryCode: initialCode)
    }
    func loginPassword(username: String, password: String) async throws -> AccountSession {
        if delaysLogin { try await Task.sleep(for: .seconds(10)) }
        guard users[username]?.password == password else { throw AccountError.invalidCredentials }
        return try issue(username)
    }
    func recoverPassword(username: String, recoveryCode: String, newPassword: String) async throws -> RecoveryMaterial {
        guard users[username]?.recoveryCode == recoveryCode else { throw AccountError.invalidRecovery }
        let code = freshCode()
        users[username]?.password = newPassword; users[username]?.recoveryCode = code
        revoke(username)
        return RecoveryMaterial(username: username, code: code)
    }
    func changePassword(token: String, password: String, newPassword: String) async throws -> AccountSession {
        let username = try userFor(token, password: password)
        users[username]?.password = newPassword; revoke(username)
        return try issue(username)
    }
    func rotateRecoveryCode(token: String, password: String) async throws -> RecoveryRotation {
        let username = try userFor(token, password: password), code = freshCode()
        users[username]?.recoveryCode = code; revoke(username)
        return RecoveryRotation(session: try issue(username), recoveryCode: code)
    }
    func weChatBindingChallenge(token: String, password: String) async throws -> LoginChallenge {
        let username = try userFor(token, password: password)
        let challenge = UUID().uuidString
        bindings[challenge] = username
        return LoginChallenge(challenge: challenge, nonce: "preview", expiresAt: Date.now.timeIntervalSince1970 + 300)
    }
    func bindWeChat(token: String, challenge: String, code: String) async throws -> AppAccount {
        guard let current = sessions[token], bindings.removeValue(forKey: challenge) == current.username else { throw AccountError.bindingExpired }
        users[current.username]?.bound = true
        return try profile(current.username, method: current.method)
    }
    func unbindWeChat(token: String, password: String) async throws -> BindingResult {
        let username = try userFor(token, password: password)
        let method = sessions[token]?.method
        users[username]?.bound = false
        sessions = sessions.filter { !($0.value.username == username && $0.value.method == "wechat") }
        return BindingResult(account: try profile(username, method: "password"), session: method == "wechat" ? try issue(username) : nil)
    }
}

@MainActor final class PasswordPreviewWeChat: WeChatAuthorizing {
    var availability: WeChatAvailability
    init(available: Bool) { availability = available ? .available : .notInstalled }
    func authorize(state: String) async throws -> String { "preview-wx-code" }
    func cancel() {}
    func handle(url: URL) {}
    func handle(activity: NSUserActivity) {}
}
#endif
