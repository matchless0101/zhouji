import SwiftUI
import UIKit

struct AuthenticationPage<Content: View>: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AccountStore.self) private var account
    let title: String
    let subtitle: String
    let showsBack: Bool
    let content: Content

    init(title: String, subtitle: String, showsBack: Bool = true, @ViewBuilder content: () -> Content) {
        self.title = title; self.subtitle = subtitle; self.showsBack = showsBack; self.content = content()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                ZJPaperHeader(title: title, subtitle: subtitle, illustration: "LiuliHeart")
                content
            }
            .padding(.horizontal, ZJTheme.pagePadding)
            .padding(.top, 12)
            .padding(.bottom, 28)
            .frame(maxWidth: 600)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(ZJTheme.pageBackground.ignoresSafeArea())
        .safeAreaInset(edge: .top, spacing: 0) {
            if showsBack {
                ZJBackButton {
                    account.cancelCredentialOperation()
                    dismiss()
                }
                .accessibilityIdentifier("account.auth.back")
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, ZJTheme.pagePadding - 6)
                .background(ZJTheme.pageBackground)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .tint(ZJTheme.accent)
    }
}

struct PrintedUsernameField: View {
    @Binding var text: String
    let identifier: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("用户名").font(ZJTheme.handwriting(21, relativeTo: .headline))
            TextField("4–32 位字母、数字或下划线", text: $text)
                .font(ZJTheme.handwriting(20, relativeTo: .body))
                .textContentType(.username)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.asciiCapable)
                .padding(16)
                .zjPaperCard()
                .accessibilityLabel("用户名")
                .accessibilityIdentifier(identifier)
            if !text.isEmpty && !PasswordCredentials.isValidUsername(text) {
                Text("使用 4–32 位英文字母、数字或下划线，字母不区分大小写。")
                    .font(.footnote).foregroundStyle(ZJTheme.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct PrintedPasswordField: View {
    let title: String
    @Binding var text: String
    let identifier: String
    var isNew = false
    @State private var showsPassword = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(ZJTheme.handwriting(21, relativeTo: .headline))
            HStack(spacing: 8) {
                Group {
                    if showsPassword { TextField("15–128 个字符", text: $text) }
                    else { SecureField("15–128 个字符", text: $text) }
                }
                .font(.body)
                .textContentType(isNew ? .newPassword : .password)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .privacySensitive()
                .accessibilityLabel(title)
                .accessibilityIdentifier(identifier)
                Button {
                    showsPassword.toggle()
                } label: {
                    Image(systemName: showsPassword ? "eye.slash" : "eye")
                        .frame(width: 44, height: 44)
                }
                .foregroundStyle(ZJTheme.secondaryInk)
                .accessibilityLabel(showsPassword ? "隐藏\(title)" : "显示\(title)")
            }
            .padding(.leading, 16)
            .padding(.trailing, 4)
            .padding(.vertical, 6)
            .zjPaperCard()
        }
    }
}

struct AuthenticationStatus: View {
    @Environment(AccountStore.self) private var account
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if account.isWaitingForWeChat {
                HStack {
                    ProgressView("等待微信授权…")
                    Spacer()
                    Button("取消") { account.cancelCredentialOperation() }
                }
            } else if account.isBusy { ProgressView("正在处理…") }
            if let message = account.message {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(ZJTheme.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("account.auth.message")
            }
        }
    }
}
