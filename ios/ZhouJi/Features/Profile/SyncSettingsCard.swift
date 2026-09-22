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

    private var token: String? { account.syncToken }

    private var canSync: Bool {
        sync.isEnabled && account.account != nil
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
                        Text("请先打开此账户的本机记录，再执行同步。")
                            .font(.footnote)
                            .foregroundStyle(ZJTheme.secondaryInk)
                    } else {
                        Text("仅同步任务、目标与已结束计时。冲突会保留双方供你选择；离线仍可本机使用。")
                            .font(.footnote)
                            .foregroundStyle(ZJTheme.secondaryInk)

                        HStack(spacing: 10) {
                            Button("同步变更") {
                                guard let token else { return }
                                Task {
                                    try? await sync.pushPending(
                                        context: modelContext,
                                        token: token,
                                        scope: libraries.current.scope
                                    )
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(!canSync || sync.isBusy || token == nil)
                            .accessibilityIdentifier("sync.pushPending")

                            Button("上传全部") { showsUploadConfirm = true }
                                .buttonStyle(.bordered)
                                .disabled(!canSync || sync.isBusy || token == nil)
                                .accessibilityIdentifier("sync.upload")

                            Button("从云端恢复") { showsRestoreConfirm = true }
                                .buttonStyle(.bordered)
                                .disabled(!canSync || sync.isBusy || token == nil)
                                .accessibilityIdentifier("sync.restore")
                        }

                        if sync.needsFullReconcile {
                            Text("需要完整对账：请使用「上传全部」，期间仍可本机记事与导出。")
                                .font(.footnote)
                                .foregroundStyle(ZJTheme.timerAccent)
                                .accessibilityIdentifier("sync.fullReconcile")
                        }

                        if !sync.conflicts.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("待处理冲突（\(sync.conflicts.count)）")
                                    .font(.subheadline.weight(.semibold))
                                ForEach(sync.conflicts) { conflict in
                                    conflictRow(conflict)
                                }
                            }
                            .accessibilityIdentifier("sync.conflicts")
                        }

                        if sync.localOnlyCount > 0 {
                            Text("本机保留副本 \(sync.localOnlyCount) 项：云端记录已永久删除；这些副本仅存于本机，不再上传。")
                                .font(.footnote)
                                .foregroundStyle(ZJTheme.timerAccent)
                                .accessibilityIdentifier("sync.localOnlyCopies")
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
                        Text("云端序号 \(sync.latestSeq)")
                            .font(.caption2)
                            .foregroundStyle(ZJTheme.secondaryInk)
                            .accessibilityIdentifier("sync.latestSeq")
                    }
                }
                .padding(16)
                .zjCard()
                .task {
                    sync.reloadJournal(scope: libraries.current.scope)
                    if let token { await sync.refreshStatus(token: token) }
                }
                .confirmationDialog("上传本机全部记录？", isPresented: $showsUploadConfirm, titleVisibility: .visible) {
                    Button("上传") {
                        guard let token else { return }
                        Task {
                            try? await sync.uploadLibrary(
                                context: modelContext,
                                token: token,
                                scope: libraries.current.scope
                            )
                        }
                    }
                } message: {
                    Text("将上传当前账户本机库中尚未写入云端的记录。不会自动合并游客记录。")
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

    private func conflictRow(_ conflict: SyncJournalConflict) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(conflictTitle(conflict))
                .font(.footnote.weight(.medium))
            if isPurgedCloudConflict(conflict) {
                Text("云端记录已永久删除；你可以保留一份仅存于本机、不再上传的副本。")
                    .font(.caption)
                    .foregroundStyle(ZJTheme.secondaryInk)
            }
            HStack {
                Button(isPurgedCloudConflict(conflict) ? "保留本机副本" : "保留本机") {
                    resolve(conflict, keepLocal: true)
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("sync.conflict.local.\(conflict.entityId)")
                Button(isPurgedCloudConflict(conflict) ? "接受云端删除" : "使用云端") {
                    resolve(conflict, keepLocal: false)
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("sync.conflict.cloud.\(conflict.entityId)")
            }
            .disabled(sync.isBusy || token == nil)
        }
        .padding(10)
        .background(ZJTheme.mutedSurface.opacity(0.55), in: RoundedRectangle(cornerRadius: 10))
    }

    private func resolve(_ conflict: SyncJournalConflict, keepLocal: Bool) {
        guard let token else { return }
        Task {
            await sync.resolveConflict(
                conflict,
                keepLocal: keepLocal,
                context: modelContext,
                token: token,
                scope: libraries.current.scope
            )
        }
    }

    private func conflictTitle(_ conflict: SyncJournalConflict) -> String {
        if isPurgedCloudConflict(conflict) {
            switch conflict.entityType {
            case "goal": return "目标（云端记录已永久删除）"
            case "task": return "任务（云端记录已永久删除）"
            default: return "计时（云端记录已永久删除）"
            }
        }
        switch conflict.entityType {
        case "goal":
            if case .string(let name) = conflict.serverPayload["name"] { return "目标「\(name)」" }
            return "目标"
        case "task":
            if case .string(let title) = conflict.serverPayload["title"] { return "任务「\(title)」" }
            return "任务"
        default:
            if case .string(let title) = conflict.serverPayload["taskTitleSnapshot"] {
                return "计时「\(title)」"
            }
            return "计时"
        }
    }

    private func isPurgedCloudConflict(_ conflict: SyncJournalConflict) -> Bool {
        conflict.serverDeletedAt != nil && conflict.serverPayload.isEmpty
    }
}
