import SwiftUI

struct PasswordRecoveryView: View {
    @Environment(AccountStore.self) private var account
    let onRecovered: (RecoveryMaterial) -> Void
    @State private var username = ""
    @State private var recoveryCode = ""
    @State private var password = ""
    @State private var confirmation = ""

    var body: some View {
        AuthenticationPage(title: "找回密码", subtitle: "用你保存的恢复码，重新回来。") {
            PrintedUsernameField(text: $username, identifier: "account.password.recover.username")
            VStack(alignment: .leading, spacing: 8) {
                Text("恢复码").font(ZJTheme.handwriting(21, relativeTo: .headline))
                TextField("输入注册时保存的恢复码", text: $recoveryCode)
                    .font(.system(.body, design: .monospaced))
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .privacySensitive()
                    .padding(16).zjPaperCard()
                    .accessibilityIdentifier("account.password.recover.code")
            }
            PrintedPasswordField(title: "新密码", text: $password, identifier: "account.password.recover.password", isNew: true)
            PrintedPasswordField(title: "确认新密码", text: $confirmation, identifier: "account.password.recover.confirmation", isNew: true)
            Text("重置后所有设备需重新登录，旧恢复码将被替换。若密码和恢复码都丢失，无法找回账户。")
                .font(.footnote).foregroundStyle(ZJTheme.secondaryInk)
            AuthenticationStatus()
            Button("重设密码") {
                Task {
                    if let material = await account.recoverPassword(username: username, recoveryCode: recoveryCode, newPassword: password) {
                        password = ""; confirmation = ""; recoveryCode = ""; onRecovered(material)
                    }
                }
            }
            .buttonStyle(ZJPrintedButtonStyle())
            .disabled(account.isBusy || !PasswordCredentials.isValidUsername(username)
                      || !PasswordCredentials.isValidRecoveryCode(recoveryCode)
                      || !PasswordCredentials.isValidPassword(password) || password != confirmation)
            .accessibilityIdentifier("account.password.recover.submit")
        }
        .onDisappear { password = ""; confirmation = ""; recoveryCode = "" }
    }
}
