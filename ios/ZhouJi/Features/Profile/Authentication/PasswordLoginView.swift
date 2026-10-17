import SwiftUI

private enum PasswordRoute: Hashable { case register, recover }

struct PasswordLoginView: View {
    @Environment(AccountStore.self) private var account
    @Environment(\.dismiss) private var dismiss
    @State private var username = ""
    @State private var password = ""
    @State private var path: [PasswordRoute] = []
    @State private var recovery: RecoveryMaterial?

    var body: some View {
        NavigationStack(path: $path) {
            AuthenticationPage(title: "账号登录", subtitle: "回到自己的小小记录。") {
                PrintedUsernameField(text: $username, identifier: "account.password.login.username")
                PrintedPasswordField(title: "密码", text: $password, identifier: "account.password.login.password")
                AuthenticationStatus()
                Button("登录") {
                    Task {
                        if await account.loginPassword(username: username, password: password) { password = ""; dismiss() }
                    }
                }
                .buttonStyle(ZJPrintedButtonStyle())
                .disabled(account.isBusy || !PasswordCredentials.isValidUsername(username) || !PasswordCredentials.isValidPassword(password))
                .accessibilityIdentifier("account.password.login.submit")
                HStack {
                    Button("注册账号") { account.message = nil; path.append(.register) }
                        .accessibilityIdentifier("account.password.registerOpen")
                    Spacer()
                    Button("忘记密码") { account.message = nil; path.append(.recover) }
                        .accessibilityIdentifier("account.password.recoverOpen")
                }
                .font(ZJTheme.handwriting(18, relativeTo: .body))
                .frame(minHeight: 44)
                .disabled(account.isBusy)
                Text("未登录也可以继续记录，任务和计时默认保存在本机。")
                    .font(.footnote).foregroundStyle(ZJTheme.secondaryInk)
            }
            .navigationDestination(for: PasswordRoute.self) { route in
                switch route {
                case .register: PasswordRegistrationView()
                case .recover: PasswordRecoveryView { recovery = $0 }
                }
            }
        }
        .interactiveDismissDisabled(account.isBusy)
        .fullScreenCover(item: $recovery, onDismiss: {
            if account.account != nil { dismiss() }
            else { path = []; account.message = "密码已重置，请使用新密码登录。" }
        }) { material in
            RecoveryCodeView(material: material) { recovery = nil }
        }
        .onAppear { if !account.isBusy { account.message = nil } }
        .onDisappear { password = "" }
    }
}
