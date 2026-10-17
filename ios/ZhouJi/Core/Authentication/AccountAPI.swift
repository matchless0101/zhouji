import Foundation

struct LoginChallenge: Codable, Sendable {
    let challenge: String
    let nonce: String
    let expiresAt: Double
}

struct AppAccount: Codable, Equatable, Sendable {
    let id: String
    let provider: String
    var nickname: String? = nil
    var avatar: String? = nil
    var hasPassword = false
    var weChatBound = false
    var username: String? = nil

    init(id: String, provider: String, nickname: String? = nil, avatar: String? = nil,
         hasPassword: Bool = false, weChatBound: Bool = false, username: String? = nil) {
        self.id = id; self.provider = provider; self.nickname = nickname; self.avatar = avatar
        self.hasPassword = hasPassword; self.weChatBound = weChatBound; self.username = username
    }

    enum CodingKeys: String, CodingKey {
        case id, provider, nickname, avatar, hasPassword, username
        case weChatBound = "wechatBound"
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(String.self, forKey: .id)
        provider = try values.decode(String.self, forKey: .provider)
        nickname = try values.decodeIfPresent(String.self, forKey: .nickname)
        avatar = try values.decodeIfPresent(String.self, forKey: .avatar)
        hasPassword = try values.decodeIfPresent(Bool.self, forKey: .hasPassword) ?? false
        weChatBound = try values.decodeIfPresent(Bool.self, forKey: .weChatBound) ?? false
        username = try values.decodeIfPresent(String.self, forKey: .username)
    }

    var providerName: String {
        switch provider {
        case "wechat": "微信登录"
        case "apple": "Apple 登录"
        case "password": "账号登录"
        default: "账户登录"
        }
    }
    var providerIcon: String {
        switch provider {
        case "wechat": "message.fill"
        case "apple": "apple.logo"
        default: "person.crop.circle"
        }
    }

    var displayName: String {
        guard let nickname, !nickname.isEmpty else { return "粥记用户" }
        return nickname
    }
}

struct AccountSession: Codable, Sendable {
    let token: String
    let expiresAt: Double
    var account: AppAccount
    var appleUser: String?
}

enum AccountError: LocalizedError, Equatable {
    case expired, unavailable, invalidResponse, keychain, reauthenticate, invalidAuthorization, invalidProfile
    case invalidCredentials, invalidRecovery, invalidInput, usernameTaken, rateLimited
    case credentialsChanged, weChatInUse, weChatAlreadyBound, bindingExpired, passwordUnavailable

    var errorDescription: String? {
        switch self {
        case .expired: "登录已过期，请重新登录。"
        case .unavailable: "暂时无法连接登录服务，请检查网络后重试。"
        case .invalidResponse: "登录服务响应异常，请稍后重试。"
        case .keychain: "无法安全保存登录状态，请解锁设备后重试。"
        case .reauthenticate: "为保护账户，请退出后重新登录，再注销账户。"
        case .invalidAuthorization: "Apple 授权未完成，请重新尝试。"
        case .invalidProfile: "昵称需为 1–20 个字符，不能包含换行或隐藏字符。"
        case .invalidCredentials: "用户名或密码不正确，请检查后重试。"
        case .invalidRecovery: "用户名或恢复码不正确，请检查后重试。"
        case .invalidInput: "请检查用户名、密码或恢复码是否符合要求。"
        case .usernameTaken: "此用户名已被使用，请换一个。"
        case .rateLimited: "尝试过于频繁，请稍后重试。"
        case .credentialsChanged: "账户凭据已更新，请重新尝试。"
        case .weChatInUse: "此微信已关联其他粥记账户，暂不支持合并。"
        case .weChatAlreadyBound: "请先解绑当前微信，再绑定其他微信。"
        case .bindingExpired: "绑定请求已失效，请重新操作。"
        case .passwordUnavailable: "此账户未设置用户名密码。"
        }
    }
}

/// The editor and save operation share the server's Unicode nickname rules.
enum ProfileNickname {
    // Python str.strip() retains zero-width spaces and trims these four C0 separators.
    private static let whitespace = CharacterSet.whitespacesAndNewlines
        .subtracting(CharacterSet(charactersIn: "\u{200B}"))
        .union(CharacterSet(charactersIn: "\u{001C}\u{001D}\u{001E}\u{001F}"))

    static func normalize(_ value: String) -> String {
        value.trimmingCharacters(in: whitespace).precomposedStringWithCanonicalMapping
    }

    static func isValid(_ value: String) -> Bool {
        guard (1...20).contains(value.unicodeScalars.count) else { return false }
        var hasVisibleCharacter = false
        for scalar in value.unicodeScalars {
            switch scalar.properties.generalCategory {
            case .control, .surrogate, .lineSeparator, .paragraphSeparator:
                return false
            case .format:
                // Joiners are needed in real names and emoji, but cannot make a name on their own.
                if scalar.value != 0x200C && scalar.value != 0x200D { return false }
            case .uppercaseLetter, .lowercaseLetter, .titlecaseLetter, .modifierLetter, .otherLetter,
                 .decimalNumber, .letterNumber, .otherNumber,
                 .mathSymbol, .currencySymbol, .modifierSymbol, .otherSymbol,
                 .connectorPunctuation, .dashPunctuation, .openPunctuation, .closePunctuation,
                 .initialPunctuation, .finalPunctuation, .otherPunctuation:
                hasVisibleCharacter = true
            default:
                break
            }
        }
        return hasVisibleCharacter
    }
}

protocol AccountServing: Sendable {
    func challenge() async throws -> LoginChallenge
    func weChatChallenge() async throws -> LoginChallenge
    func loginWeChat(challenge: String, code: String) async throws -> AccountSession
    func login(challenge: String, code: String, identityToken: String) async throws -> AccountSession
    func account(token: String) async throws -> AppAccount
    func updateProfile(token: String, nickname: String, avatar: String) async throws -> AppAccount
    func logout(token: String) async throws
    func delete(token: String) async throws
    func registerPassword(username: String, password: String) async throws -> PasswordRegistration
    func loginPassword(username: String, password: String) async throws -> AccountSession
    func recoverPassword(username: String, recoveryCode: String, newPassword: String) async throws -> RecoveryMaterial
    func changePassword(token: String, password: String, newPassword: String) async throws -> AccountSession
    func rotateRecoveryCode(token: String, password: String) async throws -> RecoveryRotation
    func weChatBindingChallenge(token: String, password: String) async throws -> LoginChallenge
    func bindWeChat(token: String, challenge: String, code: String) async throws -> AppAccount
    func unbindWeChat(token: String, password: String) async throws -> BindingResult
}

struct AccountAPI: AccountServing {
    let baseURL: URL
    let session: URLSession

    init(baseURL: URL = URL(string: "https://zhouji.xiangdangdang.top/api/v1/")!,
         session: URLSession = URLSession(configuration: .ephemeral)) {
        self.baseURL = baseURL
        self.session = session
    }

    func challenge() async throws -> LoginChallenge {
        try await decode("auth/apple/challenge", method: "POST")
    }

    func login(challenge: String, code: String, identityToken: String) async throws -> AccountSession {
        let body = try JSONSerialization.data(withJSONObject: [
            "challenge": challenge, "code": code, "identity_token": identityToken
        ])
        return try await decode("auth/apple", method: "POST", body: body)
    }

    func weChatChallenge() async throws -> LoginChallenge {
        try await decode("auth/wechat/challenge", method: "POST")
    }

    func loginWeChat(challenge: String, code: String) async throws -> AccountSession {
        let body = try JSONSerialization.data(withJSONObject: ["challenge": challenge, "code": code])
        return try await decode("auth/wechat", method: "POST", body: body)
    }

    func account(token: String) async throws -> AppAccount {
        try await decode("account", token: token)
    }

    func updateProfile(token: String, nickname: String, avatar: String) async throws -> AppAccount {
        let body = try JSONSerialization.data(withJSONObject: ["nickname": nickname, "avatar": avatar])
        return try await decode("account/profile", method: "PATCH", token: token, body: body)
    }

    func logout(token: String) async throws {
        _ = try await request("auth/logout", method: "POST", token: token)
    }

    func delete(token: String) async throws {
        _ = try await request("account", method: "DELETE", token: token)
    }

    func registerPassword(username: String, password: String) async throws -> PasswordRegistration {
        try await decode("auth/password/register", method: "POST", body: json(["username": username, "password": password]))
    }

    func loginPassword(username: String, password: String) async throws -> AccountSession {
        try await decode("auth/password/login", method: "POST", body: json(["username": username, "password": password]))
    }

    func recoverPassword(username: String, recoveryCode: String, newPassword: String) async throws -> RecoveryMaterial {
        let result: RecoveryResponse = try await decode("auth/password/recover", method: "POST",
            body: json(["username": username, "recovery_code": recoveryCode, "new_password": newPassword]))
        return RecoveryMaterial(username: result.username, code: result.recoveryCode)
    }

    func changePassword(token: String, password: String, newPassword: String) async throws -> AccountSession {
        try await decode("account/password/change", method: "POST", token: token,
            body: json(["password": password, "new_password": newPassword]))
    }

    func rotateRecoveryCode(token: String, password: String) async throws -> RecoveryRotation {
        try await decode("account/password/recovery-code", method: "POST", token: token, body: json(["password": password]))
    }

    func weChatBindingChallenge(token: String, password: String) async throws -> LoginChallenge {
        try await decode("account/wechat/binding/challenge", method: "POST", token: token, body: json(["password": password]))
    }

    func bindWeChat(token: String, challenge: String, code: String) async throws -> AppAccount {
        let result: BindingResult = try await decode("account/wechat/binding", method: "POST", token: token,
            body: json(["challenge": challenge, "code": code]))
        return result.account
    }

    func unbindWeChat(token: String, password: String) async throws -> BindingResult {
        try await decode("account/wechat/binding", method: "DELETE", token: token, body: json(["password": password]))
    }

    private func json(_ values: [String: String]) throws -> Data { try JSONSerialization.data(withJSONObject: values) }

    private func decode<T: Decodable>(_ path: String, method: String = "GET",
                                     token: String? = nil, body: Data? = nil) async throws -> T {
        let data = try await request(path, method: method, token: token, body: body)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        do { return try decoder.decode(T.self, from: data) }
        catch { throw AccountError.invalidResponse }
    }

    private func request(_ path: String, method: String, token: String? = nil, body: Data? = nil) async throws -> Data {
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = method
        request.timeoutInterval = 25
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if body != nil { request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        let data: Data
        let response: URLResponse
        do { (data, response) = try await session.data(for: request) }
        catch { throw AccountError.unavailable }
        guard let http = response as? HTTPURLResponse else { throw AccountError.invalidResponse }
        switch http.statusCode {
        case 200..<300: return data
        default: throw Self.responseError(status: http.statusCode, path: path, data: data)
        }
    }

    static func responseError(status: Int, path: String, data: Data) -> AccountError {
        if let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let detail = root["detail"] as? [String: Any], let code = detail["code"] as? String {
            switch code {
            case "invalid_credentials": return .invalidCredentials
            case "invalid_recovery": return .invalidRecovery
            case "username_taken": return .usernameTaken
            case "credentials_changed": return .credentialsChanged
            case "wechat_in_use": return .weChatInUse
            case "wechat_already_bound": return .weChatAlreadyBound
            case "binding_expired", "invalid_wechat": return .bindingExpired
            case "password_unavailable": return .passwordUnavailable
            default: break
            }
        }
        switch status {
        case 401: return .expired
        case 403: return .reauthenticate
        case 422: return path == "account/profile" ? .invalidProfile : .invalidInput
        case 429: return .rateLimited
        default: return .unavailable
        }
    }
}
