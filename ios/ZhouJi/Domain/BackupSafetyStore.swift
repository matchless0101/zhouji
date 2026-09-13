import Foundation
import SwiftData

/// One private protection copy per local library. It contains local content only, never authentication credentials.
enum BackupSafetyStore {
    private static var fileURL: URL {
        URL.applicationSupportDirectory.appendingPathComponent("RestoreProtection", isDirectory: true)
            .appendingPathComponent("before-restore.json")
    }

    @MainActor static func fileURL(in context: ModelContext) -> URL {
        let scope = LibraryScope.of(context)
        if scope == LibraryScope.guest { return fileURL }
        return fileURL.deletingLastPathComponent().appendingPathComponent(scope + ".json")
    }

    @MainActor static func exists(in context: ModelContext) -> Bool {
        FileManager.default.fileExists(atPath: fileURL(in: context).path)
    }

    @MainActor static func save(_ data: Data, in context: ModelContext) throws {
        let url = fileURL(in: context)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

}
