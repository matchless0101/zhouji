import SwiftUI

struct LocalLibraryCard: View {
    @Environment(LocalLibraryStore.self) private var libraries
    @Environment(AccountStore.self) private var account
    private var isGuest: Bool { libraries.current.scope == LibraryScope.guest }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(isGuest ? "当前：游客记录" : "当前：账户的本机记录")
                .font(.headline)
                .accessibilityIdentifier("library.current")
            Text("升级前的记录保留在游客记录中。不同账户各自保存，切换不会合并，云同步尚未上线。")
                .font(.footnote)
                .foregroundStyle(ZJTheme.secondaryInk)
            if isGuest, libraries.authenticatedScope != nil {
                Button("打开此账户的记录") { libraries.showAccount() }
                    .accessibilityIdentifier("library.account")
                    .disabled(account.isBusy)
            } else if !isGuest {
                Button("查看游客记录") { libraries.showGuest() }
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
        .zjCard()
    }
}
