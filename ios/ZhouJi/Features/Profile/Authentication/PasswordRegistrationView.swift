import SwiftUI

struct PasswordRegistrationView: View {
    @Environment(AccountStore.self) private var account
    @State private var username = ""
    @State private var password = ""
    @State private var confirmation = ""

    var body: some View {
        AuthenticationPage(title: "注册账号", subtitle: "给每一点积累，一个名字。") {
            PrintedUsernameField(text: $username, identifier: "account.password.register.username")
            PrintedPasswordField(title: "密码", text: $password, identifier: "account.password.register.password", isNew: true)
            PrintedPasswordField(title: "确认密码", text: $confirmation, identifier: "account.password.register.confirmation", isNew: true)
            Text("密码使用 15–128 个字符。用户名注册后暂不支持修改，昵称可随时调整。")
                .font(.footnote).foregroundStyle(ZJTheme.secondaryInk)
            if !confirmation.isEmpty && password != confirmation {
                Text("两次输入的密码不一致。")
                    .font(.footnote).foregroundStyle(ZJTheme.accent)
            }
            AuthenticationStatus()
            Button("注册并保存恢复码") {
                Task {
                    if await account.registerPassword(username: username, password: password) != nil {
                        password = ""; confirmation = ""
                    }
                }
            }
            .buttonStyle(ZJPrintedButtonStyle())
            .disabled(account.isBusy || !PasswordCredentials.isValidUsername(username)
                      || !PasswordCredentials.isValidPassword(password) || password != confirmation)
            .accessibilityIdentifier("account.password.register.submit")
            Text("注册后请保存恢复码。无需绑定邮箱或手机号。")
                .font(.footnote).foregroundStyle(ZJTheme.secondaryInk)
            Link("隐私政策", destination: URL(string: "https://zhouji.xiangdangdang.top/privacy/")!)
                .font(.footnote).frame(minHeight: 44)
        }
        .onDisappear { password = ""; confirmation = "" }
    }
}
