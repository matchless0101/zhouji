import AuthenticationServices
import SwiftUI

struct AccountControls: View {
    @Environment(AccountStore.self) private var account
    @Environment(\.colorScheme) private var colorScheme
    @State private var showsDeletion = false
    @State private var showsLogout = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if account.account == nil {
                Text("登录后可保留账户身份。云同步尚未上线，当前数据仍仅保存在本机。")
                    .font(.footnote)
                    .foregroundStyle(ZJTheme.secondaryInk)
                if let challenge = account.challenge {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        SignInWithAppleButton(.signIn) { request in
                            account.configure(request)
                        } onCompletion: { result in
                            Task {
                                await account.complete(result)
                                if account.account == nil { await account.prepare() }
                            }
                        }
                        .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
                        .frame(height: 50)
                        .disabled(account.isBusy || challenge.expiresAt <= context.date.timeIntervalSince1970)
                        .accessibilityIdentifier("account.appleLogin")
                        if challenge.expiresAt <= context.date.timeIntervalSince1970 {
                            Button("刷新登录请求") { Task { await account.prepare() } }
                        }
                    }
                } else if account.isPreparing {
                    ProgressView("正在准备登录…")
                } else {
                    Button("准备 Apple 登录") { Task { await account.prepare() } }
                        .buttonStyle(.bordered)
                        .accessibilityIdentifier("account.retry")
                }
                Button { Task { await account.loginWeChat() } } label: {
                    Label("微信登录", systemImage: "message.fill")
                        .font(.body.weight(.medium))
                        .frame(maxWidth: .infinity, minHeight: 50)
                }
                .foregroundStyle(.white)
                .background(Color(red: 0.03, green: 0.65, blue: 0.28), in: RoundedRectangle(cornerRadius: 8))
                .disabled(account.isBusy)
                .accessibilityIdentifier("account.wechatLogin")
                Text("微信与 Apple 登录分别对应独立账户。")
                    .font(.caption)
                    .foregroundStyle(ZJTheme.secondaryInk)
            } else {
                Text("任务与计时记录仍保存在本机，云同步尚未上线。")
                    .font(.footnote)
                    .foregroundStyle(ZJTheme.secondaryInk)
                HStack {
                    Button("退出登录") { showsLogout = true }
                        .disabled(account.isBusy)
                        .accessibilityIdentifier("account.logout")
                    Spacer()
                    Button("注销账户", role: .destructive) { showsDeletion = true }
                        .disabled(account.isBusy)
                        .accessibilityIdentifier("account.delete")
                }
            }
            if account.isWaitingForWeChat {
                HStack {
                    ProgressView("等待微信授权…")
                    Spacer()
                    Button("取消") { account.cancelWeChat() }
                }
            } else if account.isBusy { ProgressView("正在处理…") }
            if let message = account.message {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(ZJTheme.secondaryInk)
                    .accessibilityIdentifier("account.message")
            }
        }
        .padding(16)
        .zjCard()
        .task { await account.prepare() }
        .confirmationDialog("退出登录？", isPresented: $showsLogout, titleVisibility: .visible) {
            Button("退出登录", role: .destructive) { Task { await account.logout(); await account.prepare() } }
        } message: {
            Text("本机任务、目标和计时记录会继续保留。")
        }
        .confirmationDialog("永久注销粥记账户？", isPresented: $showsDeletion, titleVisibility: .visible) {
            Button("注销账户", role: .destructive) { Task { await account.deleteAccount() } }
        } message: {
            Text(account.account?.provider == "wechat"
                 ? "将永久删除粥记服务端账户及保存的授权凭据，本机记录保留。微信中的应用授权请在微信设置中管理。"
                 : "将撤销 Apple 授权并删除粥记服务端账户，无法撤销。本机任务、目标和计时记录仍会保留。")
        }
    }
}
