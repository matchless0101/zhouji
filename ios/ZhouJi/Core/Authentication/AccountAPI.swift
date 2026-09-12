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

enum AccountError: LocalizedError {
    case expired, unavailable, invalidResponse, keychain, reauthenticate, invalidAuthorization, invalidProfile

    var errorDescription: String? {
        switch self {
        case .expired: "登录已过期，请重新登录。"
        case .unavailable: "暂时无法连接登录服务，请检查网络后重试。"
        case .invalidResponse: "登录服务响应异常，请稍后重试。"
        case .keychain: "无法安全保存登录状态，请解锁设备后重试。"
        case .reauthenticate: "为保护账户，请退出后重新登录，再注销账户。"
        case .invalidAuthorization: "Apple 授权未完成，请重新尝试。"
        case .invalidProfile: "昵称需为 1–20 个字符，不能包含换行或隐藏字符。"
        }
    }
}

protocol AccountServing: Sendable {
    func challenge() async throws -> LoginChallenge
    func login(challenge: String, code: String, identityToken: String) async throws -> AccountSession
    func account(token: String) async throws -> AppAccount
    func updateProfile(token: String, nickname: String, avatar: String) async throws -> AppAccount
    func logout(token: String) async throws
    func delete(token: String) async throws
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
        case 401: throw AccountError.expired
        case 403: throw AccountError.reauthenticate
        case 422 where path == "account/profile": throw AccountError.invalidProfile
        default: throw AccountError.unavailable
        }
    }
}
