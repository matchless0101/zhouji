import Foundation

/// Per-library sync journal: versions, conflicts, and full-reconcile flag (R4).
/// Stored as JSON under Application Support; never contains auth tokens.
struct SyncJournalEntry: Codable, Equatable, Sendable {
    var version: Int
    var updatedAt: Int
}

struct SyncJournalConflict: Codable, Equatable, Identifiable, Sendable {
    var id: String { entityType + "/" + entityId }
    let entityType: String
    let entityId: String
    let serverVersion: Int
    let serverUpdatedAt: Int
    let serverDeletedAt: Int?
    let serverPayload: [String: SyncJSONValue]
    /// Local change that lost the version race (for "keep local" retry).
    let localChange: SyncChangePayload?

    enum CodingKeys: String, CodingKey {
        case entityType = "entity_type"
        case entityId = "entity_id"
        case serverVersion = "server_version"
        case serverUpdatedAt = "server_updated_at"
        case serverDeletedAt = "server_deleted_at"
        case serverPayload = "server_payload"
        case localChange = "local_change"
    }
}

struct SyncJournal: Codable, Equatable, Sendable {
    var cursor: Int = 0
    var entries: [String: SyncJournalEntry] = [:]
    var conflicts: [SyncJournalConflict] = []
    /// Set when offline queue / entity count exceeds R4 threshold and full reconcile is required.
    var needsFullReconcile = false

    static let maxPending = 5_000

    mutating func noteApplied(entityType: String, entityId: String, version: Int, updatedAt: Int) {
        let key = entityType + "/" + entityId
        entries[key] = SyncJournalEntry(version: version, updatedAt: updatedAt)
        conflicts.removeAll { $0.entityType == entityType && $0.entityId == entityId }
    }

    mutating func noteConflict(_ conflict: SyncJournalConflict) {
        conflicts.removeAll { $0.id == conflict.id }
        conflicts.append(conflict)
        if conflicts.count > 100 {
            conflicts.removeFirst(conflicts.count - 100)
        }
    }
}

struct SyncJournalStore {
    private let fileURL: URL

    init(directory: URL, scope: String) {
        fileURL = directory.appendingPathComponent("sync-journal-" + scope + ".json")
    }

    func load() -> SyncJournal {
        guard let data = try? Data(contentsOf: fileURL) else { return SyncJournal() }
        return (try? JSONDecoder().decode(SyncJournal.self, from: data)) ?? SyncJournal()
    }

    func save(_ journal: SyncJournal) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(journal)
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
}
