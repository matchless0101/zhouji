import SwiftUI

struct LocalLibraryCard: View {
    @Environment(LocalLibraryStore.self) private var libraries
    @Environment(AccountStore.self) private var account
    private var isGuest: Bool { libraries.current.scope == LibraryScope.guest }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: "folder.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(ZJTheme.success)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 6) {
                    Text(isGuest ? "当前：游客记录" : "当前：账户的本机记录")
                        .font(ZJTheme.handwriting(19, relativeTo: .headline).weight(.bold))
                        .accessibilityIdentifier("library.current")
                    Text(isGuest ? "升级前的记录保留在游客记录中。不同账户各自保存，切换不会合并。" : "不同账户各自保存，切换不会合并。")
                        .font(ZJTheme.handwriting(15, relativeTo: .footnote))
                        .foregroundStyle(ZJTheme.secondaryInk)
                }
                .fixedSize(horizontal: false, vertical: true)
            }
            if isGuest, libraries.authenticatedScope != nil {
                Button("打开此账户的记录") { libraries.showAccount() }
                    .buttonStyle(ZJPaperButtonStyle())
                    .accessibilityIdentifier("library.account")
                    .disabled(account.isBusy)
            } else if !isGuest {
                Button("查看游客记录") { libraries.showGuest() }
                    .buttonStyle(ZJPaperButtonStyle())
                    .accessibilityIdentifier("library.guest")
                    .disabled(account.isBusy)
                if libraries.authenticatedScope == nil {
                    Text("这份账户记录仅供本机离线使用。请重新登录原账户以恢复登录状态。")
                        .font(.footnote)
                        .foregroundStyle(ZJTheme.secondaryInk)
                }
            }
            if let message = libraries.message {
                Text(message).font(.footnote).foregroundStyle(ZJTheme.secondaryInk)
                    .accessibilityIdentifier("library.message")
            }
        }
        .padding(16)
        .zjPaperCard()
    }
}
