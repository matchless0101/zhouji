import Foundation

/// One private local protection copy. It contains local content only, never authentication credentials.
enum BackupSafetyStore {
    static var fileURL: URL {
        URL.applicationSupportDirectory.appendingPathComponent("RestoreProtection", isDirectory: true)
            .appendingPathComponent("before-restore.json")
    }

    static var exists: Bool { FileManager.default.fileExists(atPath: fileURL.path) }

    static func save(_ data: Data) throws {
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
}
