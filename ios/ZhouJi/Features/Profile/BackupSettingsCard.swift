import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// Local versioned JSON backup. Independent of cloud sync (PRD 增量 D10).
struct BackupSettingsCard: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(TimerController.self) private var timer
    @Environment(LocalLibraryStore.self) private var libraries
    @State private var isReading = false
    @State private var protectionAvailable = false
    @State private var expectedContent: ZhouJiBackupDocument?
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
                    detail: "包含任务内容，请妥善保管",
                    systemImage: "square.and.arrow.up",
                    showsChevron: true
                )
            }
            .buttonStyle(.plain)
            .disabled(isReading)
            .accessibilityIdentifier("backup.export")

            Divider()
                .overlay(ZJTheme.divider)
                .padding(.leading, 62)

            Button {
                do {
                    try BackupStore.ensureCanRestore(in: modelContext)
                    isImporting = true
                } catch { presentedMessage = error.localizedDescription }
            } label: {
                ProfileSettingRow(
                    title: "从备份恢复",
                    detail: "校验后写入本机",
                    systemImage: "square.and.arrow.down",
                    showsChevron: true
                )
            }
            .buttonStyle(.plain)
            .disabled(isReading)
            .accessibilityIdentifier("backup.import")

            if protectionAvailable {
                Button { exportProtection() } label: {
                    ProfileSettingRow(title: "导出恢复前备份", detail: "保留最近一次恢复前的数据",
                                      systemImage: "clock.arrow.circlepath", showsChevron: true)
                }
                .buttonStyle(.plain)
                .disabled(isReading)
                .accessibilityIdentifier("backup.protection")
            }
            if libraries.authenticatedScope == nil, libraries.current.scope == LibraryScope.guest,
               let url = libraries.deletedBackupURL {
                Button { exportSavedFile(url) } label: {
                    ProfileSettingRow(title: "导出注销前备份", detail: "最近一次注销账户的本机内容",
                                      systemImage: "archivebox", showsChevron: true)
                }
                .buttonStyle(.plain)
                .disabled(isReading)
                .accessibilityIdentifier("backup.deletedAccount")
            }
            if isReading {
                ProgressView("正在校验备份…").padding(14)
            }
            Text("仅恢复到当前记录，不会上传。备份需属于同一账户或同为游客记录。")
                .font(.footnote)
                .foregroundStyle(ZJTheme.secondaryInk)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)

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
        .onAppear { protectionAvailable = BackupSafetyStore.exists(in: modelContext) }
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
                Task { await prepareImport(from: url) }
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
                expectedContent = nil
            }
        } message: {
            Text((pendingPreview?.summary ?? "") + " 同 ID 记录将按备份更新，其他本机记录保留。备份中的运行计时将恢复为暂停。")
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

    private func prepareImport(from url: URL) async {
        isReading = true
        defer { isReading = false }
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        do {
            let document = try await Task.detached { try BackupStore.readFile(url) }.value
            let preview = try BackupStore.preview(document, in: modelContext)
            expectedContent = try BackupStore.exportDocument(from: modelContext)
            pendingDocument = document
            pendingPreview = preview
            presentedMessage = nil
            showsRestoreConfirm = true
        } catch {
            pendingDocument = nil
            pendingPreview = nil
            expectedContent = nil
            presentedMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func performRestore() {
        guard let document = pendingDocument else { return }
        do {
            let result = try BackupStore.restore(document, in: modelContext, expectedContent: expectedContent)
            timer.reloadAfterBackupRestore()
            presentedMessage = result.summary
        } catch {
            presentedMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
        pendingDocument = nil
        pendingPreview = nil
        expectedContent = nil
        protectionAvailable = BackupSafetyStore.exists(in: modelContext)
    }

    private func exportProtection() { exportSavedFile(BackupSafetyStore.fileURL(in: modelContext)) }

    private func exportSavedFile(_ url: URL) {
        do {
            let data = try Data(contentsOf: url)
            // Protection files are generated locally and may legitimately contain an empty pre-import library.
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .secondsSince1970
            exportDocument = try decoder.decode(ZhouJiBackupDocument.self, from: data)
            presentedMessage = nil
            isExporting = true
        } catch { presentedMessage = "未能读取恢复前备份，请检查设备存储后重试。" }
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
