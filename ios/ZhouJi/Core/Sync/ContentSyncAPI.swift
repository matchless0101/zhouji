import Foundation

struct SyncChangePayload: Codable, Equatable, Sendable {
    let clientOpId: String
    let entityType: String
    let entityId: String
    let op: String
    let version: Int
    let updatedAt: Int
    let payload: [String: SyncJSONValue]

    enum CodingKeys: String, CodingKey {
        case clientOpId = "client_op_id"
        case entityType = "entity_type"
        case entityId = "entity_id"
        case op
        case version
        case updatedAt = "updated_at"
        case payload
    }
}

/// JSON-compatible value tree for sync payloads (no Foundation JSONSerialization types).
enum SyncJSONValue: Codable, Equatable, Sendable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case null
    case array([SyncJSONValue])
    case object([String: SyncJSONValue])

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Int.self) {
            self = .int(value)
        } else if let value = try? container.decode(Double.self) {
            self = .double(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([SyncJSONValue].self) {
            self = .array(value)
        } else if let value = try? container.decode([String: SyncJSONValue].self) {
            self = .object(value)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported JSON value")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .int(let value): try container.encode(value)
        case .double(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .null: try container.encodeNil()
        case .array(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        }
    }
}

extension SyncJSONValue: ExpressibleByStringLiteral, ExpressibleByIntegerLiteral, ExpressibleByFloatLiteral, ExpressibleByBooleanLiteral, ExpressibleByNilLiteral {
    init(stringLiteral value: String) { self = .string(value) }
    init(integerLiteral value: Int) { self = .int(value) }
    init(floatLiteral value: Double) { self = .double(value) }
    init(booleanLiteral value: Bool) { self = .bool(value) }
    init(nilLiteral: ()) { self = .null }
}

struct SyncAppliedItem: Codable, Equatable, Sendable {
    let clientOpId: String
    let entityType: String
    let entityId: String
    let version: Int
    let serverSeq: Int
    let deduped: Bool

    enum CodingKeys: String, CodingKey {
        case clientOpId = "client_op_id"
        case entityType = "entity_type"
        case entityId = "entity_id"
        case version
        case serverSeq = "server_seq"
        case deduped
    }
}

struct SyncConflictItem: Codable, Equatable, Sendable {
    let clientOpId: String
    let entityType: String
    let entityId: String
    let serverVersion: Int
    let serverUpdatedAt: Int
    let serverDeletedAt: Int?
    let serverPayload: [String: SyncJSONValue]

    enum CodingKeys: String, CodingKey {
        case clientOpId = "client_op_id"
        case entityType = "entity_type"
        case entityId = "entity_id"
        case serverVersion = "server_version"
        case serverUpdatedAt = "server_updated_at"
        case serverDeletedAt = "server_deleted_at"
        case serverPayload = "server_payload"
    }
}

struct SyncPushResponse: Codable, Equatable, Sendable {
    let applied: [SyncAppliedItem]
    let conflicts: [SyncConflictItem]
    let serverTime: Int

    enum CodingKeys: String, CodingKey {
        case applied, conflicts
        case serverTime = "server_time"
    }
}

struct SyncEntityPayload: Codable, Equatable, Sendable {
    let entityType: String
    let entityId: String
    let version: Int
    let serverSeq: Int
    let updatedAt: Int
    let deletedAt: Int?
    let payload: [String: SyncJSONValue]

    enum CodingKeys: String, CodingKey {
        case entityType = "entity_type"
        case entityId = "entity_id"
        case version
        case serverSeq = "server_seq"
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
        case payload
    }
}

struct SyncPullResponse: Codable, Equatable, Sendable {
    let entities: [SyncEntityPayload]
    let cursor: Int
    let hasMore: Bool

    enum CodingKeys: String, CodingKey {
        case entities, cursor
        case hasMore = "has_more"
    }
}

struct SyncStatusResponse: Codable, Equatable, Sendable {
    let accountId: String
    let latestSeq: Int
    let softDeletedCount: Int
    let syncEnabled: Bool

    enum CodingKeys: String, CodingKey {
        case accountId = "account_id"
        case latestSeq = "latest_seq"
        case softDeletedCount = "soft_deleted_count"
        case syncEnabled = "sync_enabled"
    }
}

protocol ContentSyncServing: Sendable {
    func push(token: String, changes: [SyncChangePayload]) async throws -> SyncPushResponse
    func pull(token: String, cursor: Int, limit: Int) async throws -> SyncPullResponse
    func status(token: String) async throws -> SyncStatusResponse
}

struct ContentSyncAPI: ContentSyncServing {
    let baseURL: URL
    let session: URLSession

    init(baseURL: URL = URL(string: "https://zhouji.xiangdangdang.top/api/v1/")!,
         session: URLSession = URLSession(configuration: .ephemeral)) {
        self.baseURL = baseURL
        self.session = session
    }

    func push(token: String, changes: [SyncChangePayload]) async throws -> SyncPushResponse {
        struct Body: Encodable { let changes: [SyncChangePayload] }
        return try await send(path: "sync/push", method: "POST", token: token, body: Body(changes: changes))
    }

    func pull(token: String, cursor: Int, limit: Int) async throws -> SyncPullResponse {
        var components = URLComponents(url: baseURL.appendingPathComponent("sync/pull"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "cursor", value: String(cursor)),
            URLQueryItem(name: "limit", value: String(limit))
        ]
        return try await send(url: components.url!, method: "GET", token: token)
    }

    func status(token: String) async throws -> SyncStatusResponse {
        try await send(path: "sync/status", method: "GET", token: token)
    }

    private func send<T: Decodable>(path: String, method: String, token: String, body: (any Encodable)? = nil) async throws -> T {
        try await send(url: baseURL.appendingPathComponent(path), method: method, token: token, body: body)
    }

    private func send<T: Decodable>(url: URL, method: String, token: String, body: (any Encodable)? = nil) async throws -> T {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 60
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let body {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            request.httpBody = try encoder.encode(AnyEncodable(body))
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let data: Data
        let response: URLResponse
        do { (data, response) = try await session.data(for: request) }
        catch { throw AccountError.unavailable }
        guard let http = response as? HTTPURLResponse else { throw AccountError.invalidResponse }
        switch http.statusCode {
        case 200..<300:
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            // Types already use explicit CodingKeys; convertFromSnakeCase would double-map.
            decoder.keyDecodingStrategy = .useDefaultKeys
            do { return try decoder.decode(T.self, from: data) }
            catch { throw AccountError.invalidResponse }
        case 401: throw AccountError.expired
        case 403: throw AccountError.reauthenticate
        default: throw AccountError.unavailable }
    }
}

private struct AnyEncodable: Encodable {
    private let encodeFunc: (Encoder) throws -> Void
    init(_ wrapped: any Encodable) { encodeFunc = wrapped.encode(to:) }
    func encode(to encoder: Encoder) throws { try encodeFunc(encoder) }
}
