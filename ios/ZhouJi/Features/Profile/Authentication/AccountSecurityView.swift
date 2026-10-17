import Observation
import SwiftUI

enum AccountSecurityAction: String, Hashable {
    case changePassword, rotateRecovery, bindWeChat, unbindWeChat

    var title: String {
        switch self {
        case .changePassword: "修改密码"
        case .rotateRecovery: "更新恢复码"
        case .bindWeChat: "绑定微信"
        case .unbindWeChat: "解绑微信"
        }
    }
}

/// Owned by the launching settings view so sheet reconstruction cannot discard recovery material.
@MainActor @Observable final class AccountSecurityFlow {
    var path: [AccountSecurityAction] = []
    var recovery: RecoveryMaterial?
}

struct AccountSecurityView: View {
    @Environment(AccountStore.self) private var account
    @Environment(\.dismiss) private var dismiss
    @Bindable var flow: AccountSecurityFlow

    var body: some View {
        Group {
            if let material = flow.recovery {
                RecoveryCodeView(material: material) { flow.recovery = nil; flow.path = [] }
            } else {
                navigation
            }
        }
        .interactiveDismissDisabled()
        .onChange(of: account.account == nil) { _, signedOut in
            if signedOut { flow.recovery = nil; flow.path = []; dismiss() }
        }
        .onAppear { account.refreshWeChatAvailability(); account.message = nil }
    }

    private var navigation: some View {
        NavigationStack(path: $flow.path) {
            AuthenticationPage(title: "账户安全", subtitle: "给自己的记录，留一把安全的钥匙。") {
                if let current = account.account, current.hasPassword {
                    Text("用户名：\(current.username ?? "")")
                        .font(ZJTheme.handwriting(22, relativeTo: .headline))
                    action(.changePassword, identifier: "changePassword")
                    action(.rotateRecovery, identifier: "rotateRecovery")
                    if current.weChatBound {
                        Text("已绑定微信，可使用微信或账号密码登录同一个账户。")
                            .font(.footnote).foregroundStyle(ZJTheme.secondaryInk)
                        action(.unbindWeChat, identifier: "unbind")
                    } else {
                        action(.bindWeChat, identifier: "bind")
                            .disabled(account.weChatAvailability != .available)
                        if account.weChatAvailability != .available {
                            Text(account.weChatAvailability == .notInstalled
                                 ? "当前设备未安装微信，暂时无法绑定；账号密码登录不受影响。"
                                 : "当前设备无法使用微信授权，暂时无法绑定；账号密码登录不受影响。")
                                .font(.footnote).foregroundStyle(ZJTheme.secondaryInk)
                        }
                    }
                    Text("绑定和解绑不会移动或删除任务与计时记录。")
                        .font(.footnote).foregroundStyle(ZJTheme.secondaryInk)
                }
            }
            .navigationDestination(for: AccountSecurityAction.self) { action in
                SecurityActionView(action: action, onDone: { flow.path = [] }, flow: flow)
                    .id(action)
            }
        }
    }

    private func action(_ action: AccountSecurityAction, identifier: String) -> some View {
        Button { flow.path.append(action) } label: {
            HStack {
                Text(action.title)
                Spacer()
                Image(systemName: "chevron.right").font(.body)
            }
        }
        .buttonStyle(ZJPaperButtonStyle())
        .disabled(account.isBusy)
        .accessibilityIdentifier("account.security.\(identifier)")
    }
}

private struct SecurityActionView: View {
    @Environment(AccountStore.self) private var account
    let action: AccountSecurityAction
    let onDone: () -> Void
    let flow: AccountSecurityFlow
    @State private var password = ""
    @State private var newPassword = ""
    @State private var confirmation = ""
    @State private var confirmsAction = false

    var body: some View {
        AuthenticationPage(title: action.title, subtitle: "先验证当前密码，再完成这一步。") {
            PrintedPasswordField(title: "当前密码", text: $password, identifier: "account.security.password")
            if action == .changePassword {
                PrintedPasswordField(title: "新密码", text: $newPassword, identifier: "account.security.newPassword", isNew: true)
                PrintedPasswordField(title: "确认新密码", text: $confirmation, identifier: "account.security.confirmation", isNew: true)
            }
            if action == .rotateRecovery {
                Text("更新后旧恢复码立即失效，其他设备需要重新登录。请保存新的恢复码。")
                    .font(.footnote).foregroundStyle(ZJTheme.secondaryInk)
            } else if action == .changePassword {
                Text("修改后其他设备需要使用新密码重新登录，恢复码保持有效。")
                    .font(.footnote).foregroundStyle(ZJTheme.secondaryInk)
            } else if action == .unbindWeChat {
                Text("解绑后仍可用账号密码登录，不会删除任务与计时记录。")
                    .font(.footnote).foregroundStyle(ZJTheme.secondaryInk)
            }
            AuthenticationStatus()
            if confirmsAction {
                Text(action == .unbindWeChat ? "确认解绑微信？账号密码仍可使用，本机记录会保留。" : "确认替换恢复码？旧码将立即失效，请保存接下来显示的新恢复码。")
                    .font(.body).foregroundStyle(ZJTheme.ink)
                Button(action == .unbindWeChat ? "确认解绑" : "替换恢复码") { perform() }
                    .buttonStyle(ZJPrintedButtonStyle())
                    .disabled(!canSubmit)
                Button("取消") { confirmsAction = false }
                    .buttonStyle(ZJPaperButtonStyle())
                    .disabled(account.isBusy)
            } else {
                Button(action.title) {
                    if action == .rotateRecovery || action == .unbindWeChat { confirmsAction = true }
                    else { perform() }
                }
                .buttonStyle(ZJPrintedButtonStyle())
                .disabled(!canSubmit)
                .accessibilityIdentifier("account.security.submit")
            }
        }
        .onDisappear { password = ""; newPassword = ""; confirmation = "" }
        .onAppear { account.message = nil }
    }

    private var canSubmit: Bool {
        !account.isBusy && PasswordCredentials.isValidPassword(password)
            && (action != .changePassword || (PasswordCredentials.isValidPassword(newPassword) && newPassword == confirmation))
    }

    private func perform() {
        Task {
            let succeeded: Bool
            switch action {
            case .changePassword: succeeded = await account.changePassword(password: password, newPassword: newPassword)
            case .rotateRecovery:
                if let material = await account.rotateRecoveryCode(password: password) {
                    password = ""; flow.recovery = material
                }
                succeeded = false
            case .bindWeChat: succeeded = await account.bindWeChat(password: password)
            case .unbindWeChat: succeeded = await account.unbindWeChat(password: password)
            }
            if succeeded { password = ""; newPassword = ""; confirmation = ""; onDone() }
        }
    }
}
