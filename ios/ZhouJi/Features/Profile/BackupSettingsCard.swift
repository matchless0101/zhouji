import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// Local versioned JSON backup. Independent of cloud sync (PRD 增量 D10).
struct BackupSettingsCard: View {
    @Environment(\.modelContext) private var modelContext
    @State private var isExporting = false
    @State private var isImporting = false
    @State private var exportDocument: ZhouJiBackupDocument?
    @State private var pendingDocument: ZhouJiBackupDocument?
    @State private var pendingPreview: BackupRestorePreview?
    @State private var presentedMessage: String?
    @State private var showsRestoreConfirm = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ProfileSettingRow(
                title: "数据备份",
                detail: "JSON 导出与恢复",
                systemImage: "arrow.down.document",
                showsChevron: false
            )
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("数据备份")

            Divider()
                .overlay(ZJTheme.divider)
                .padding(.leading, 62)

            Button {
                exportBackup()
            } label: {
                ProfileSettingRow(
                    title: "导出备份",
                    detail: "完整可恢复文件",
                    systemImage: "square.and.arrow.up",
                    showsChevron: true
                )
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("backup.export")

            Divider()
                .overlay(ZJTheme.divider)
                .padding(.leading, 62)

            Button {
                isImporting = true
            } label: {
                ProfileSettingRow(
                    title: "从备份恢复",
                    detail: "校验后写入本机",
                    systemImage: "square.and.arrow.down",
                    showsChevron: true
                )
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("backup.import")

            if let presentedMessage {
                Text(presentedMessage)
                    .font(.footnote)
                    .foregroundStyle(ZJTheme.secondaryInk)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .accessibilityIdentifier("backup.message")
            }
        }
        .zjCard()
        .fileExporter(
            isPresented: $isExporting,
            document: exportDocument.map(BackupFile.init),
            contentType: .json,
            defaultFilename: Self.exportFilename()
        ) { result in
            switch result {
            case .success:
                presentedMessage = "备份已导出。"
            case .failure(let error):
                presentedMessage = error.localizedDescription
            }
            exportDocument = nil
        }
        .fileImporter(
            isPresented: $isImporting,
            allowedContentTypes: [.json],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                prepareImport(from: url)
            case .failure(let error):
                presentedMessage = error.localizedDescription
            }
        }
        .confirmationDialog(
            "从备份恢复到本机？",
            isPresented: $showsRestoreConfirm,
            titleVisibility: .visible
        ) {
            Button("恢复") { performRestore() }
            Button("取消", role: .cancel) {
                pendingDocument = nil
                pendingPreview = nil
            }
        } message: {
            Text(pendingPreview?.summary ?? "将按备份内容新增或更新本机数据，不会删除备份中不存在的本机记录。")
        }
    }

    private func exportBackup() {
        do {
            let document = try BackupStore.exportDocument(from: modelContext)
            exportDocument = document
            presentedMessage = nil
            isExporting = true
        } catch {
            presentedMessage = error.localizedDescription
        }
    }

    private func prepareImport(from url: URL) {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        do {
            let data = try Data(contentsOf: url)
            let document = try BackupStore.decode(data)
            let preview = try BackupStore.preview(document, in: modelContext)
            pendingDocument = document
            pendingPreview = preview
            presentedMessage = nil
            showsRestoreConfirm = true
        } catch {
            pendingDocument = nil
            pendingPreview = nil
            presentedMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func performRestore() {
        guard let document = pendingDocument else { return }
        do {
            let result = try BackupStore.restore(document, in: modelContext)
            presentedMessage = result.summary
        } catch {
            presentedMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
        pendingDocument = nil
        pendingPreview = nil
    }

    private static func exportFilename() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return "ZhouJi-backup-\(formatter.string(from: .now))"
    }
}

private struct BackupFile: FileDocument {
    static let readableContentTypes: [UTType] = [.json]

    var document: ZhouJiBackupDocument

    init(_ document: ZhouJiBackupDocument) {
        self.document = document
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        document = try BackupStore.decode(data)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: try BackupStore.encode(document))
    }
}
