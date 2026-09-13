import SwiftData
import SwiftUI

/// Visible only when content sync is explicitly enabled (default off).
struct SyncSettingsCard: View {
    @Environment(AccountStore.self) private var account
    @Environment(LocalLibraryStore.self) private var libraries
    @Environment(ContentSyncStore.self) private var sync
    @Environment(\.modelContext) private var modelContext
    @State private var showsUploadConfirm = false
    @State private var showsRestoreConfirm = false

    private var token: String? {
        // Token is held privately in AccountStore session; expose only for authenticated sync calls.
        account.syncToken
    }

    private var canSync: Bool {
        sync.isEnabled && account.account != nil && !libraries.current.scope.isEmpty
            && libraries.current.scope == libraries.authenticatedScope
    }

    var body: some View {
        Group {
            if sync.isEnabled {
                VStack(alignment: .leading, spacing: 12) {
                    Text("云同步（测试）")
                        .font(.headline)
                        .accessibilityIdentifier("sync.title")
                    if account.account == nil {
                        Text("登录后才能同步到账户云端。")
                            .font(.footnote)
                            .foregroundStyle(ZJTheme.secondaryInk)
                    } else if libraries.current.scope != libraries.authenticatedScope {
                        Text("请先打开此账户的本机记录，再执行上传或恢复。")
                            .font(.footnote)
                            .foregroundStyle(ZJTheme.secondaryInk)
                    } else {
                        Text("上传会把本机任务、目标和已结束计时写入此账户；恢复会从云端拉取，不会删除本机多出的记录。仅同步已结束的计时。")
                            .font(.footnote)
                            .foregroundStyle(ZJTheme.secondaryInk)
                        HStack(spacing: 10) {
                            Button("上传本机记录") { showsUploadConfirm = true }
                                .buttonStyle(.borderedProminent)
                                .disabled(!canSync || sync.isBusy || token == nil)
                                .accessibilityIdentifier("sync.upload")
                            Button("从云端恢复") { showsRestoreConfirm = true }
                                .buttonStyle(.bordered)
                                .disabled(!canSync || sync.isBusy || token == nil)
                                .accessibilityIdentifier("sync.restore")
                        }
                        if let progress = sync.progress {
                            ProgressView(value: Double(progress.completed), total: Double(max(progress.total, 1))) {
                                Text(progress.phase)
                            }
                            .accessibilityIdentifier("sync.progress")
                        }
                        if let message = sync.message {
                            Text(message)
                                .font(.footnote)
                                .foregroundStyle(ZJTheme.secondaryInk)
                                .accessibilityIdentifier("sync.message")
                        }
                        Text("云端最新序号 \(sync.latestSeq)")
                            .font(.caption2)
                            .foregroundStyle(ZJTheme.secondaryInk)
                            .accessibilityIdentifier("sync.latestSeq")
                    }
                }
                .padding(16)
                .zjCard()
                .task {
                    if let token { await sync.refreshStatus(token: token) }
                }
                .confirmationDialog("上传本机记录到此账户？", isPresented: $showsUploadConfirm, titleVisibility: .visible) {
                    Button("上传") {
                        guard let token else { return }
                        Task { try? await sync.uploadLibrary(context: modelContext, token: token) }
                    }
                } message: {
                    Text("将上传当前账户本机库中的任务、目标与已结束计时。不会自动合并游客记录。")
                }
                .confirmationDialog("从此账户云端恢复？", isPresented: $showsRestoreConfirm, titleVisibility: .visible) {
                    Button("恢复") {
                        guard let token else { return }
                        Task {
                            try? await sync.restoreIntoLibrary(
                                context: modelContext,
                                token: token,
                                scope: libraries.current.scope
                            )
                        }
                    }
                } message: {
                    Text("将把云端记录写入本机账户库；本机多出的记录会保留。")
                }
            }
        }
    }
}
