import SwiftUI
import UIKit

struct RecoveryCodeView: View {
    @Environment(\.scenePhase) private var scenePhase
    let material: RecoveryMaterial
    let onDone: () -> Void
    @State private var copied = false

    var body: some View {
        AuthenticationPage(title: "保存恢复码", subtitle: "把这把小钥匙，收在安全的地方。", showsBack: false) {
            VStack(alignment: .leading, spacing: 16) {
                Text("用户名：\(material.username)")
                    .font(ZJTheme.handwriting(20, relativeTo: .headline))
                Text(material.code.replacingOccurrences(of: "-", with: "  "))
                    .font(.system(.title3, design: .monospaced).weight(.semibold))
                    .foregroundStyle(ZJTheme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel("恢复码")
                    .accessibilityValue(material.code.replacingOccurrences(of: "-", with: ", "))
                    .privacySensitive()
                Text("忘记密码时，可用用户名和恢复码重设密码。请存入密码管理器或其他安全位置。密码和恢复码都丢失后，无法找回账户。")
                    .font(ZJTheme.handwriting(17, relativeTo: .body))
                    .foregroundStyle(ZJTheme.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(20).zjPaperCard()
            Button("复制恢复资料") {
                UIPasteboard.general.setItems([[UIPasteboard.typeAutomatic: "粥记\n用户名：\(material.username)\n恢复码：\(material.code)"]],
                    options: [.localOnly: true, .expirationDate: Date.now.addingTimeInterval(120)])
                copied = true
            }
            .buttonStyle(ZJPaperButtonStyle())
            .accessibilityIdentifier("account.recovery.copy")
            if copied {
                Text("已复制，请尽快保存到安全位置。剪贴板内容将在两分钟后过期。")
                    .font(.footnote).foregroundStyle(ZJTheme.secondaryInk)
            }
            Button("我已妥善保存", action: onDone)
                .buttonStyle(ZJPrintedButtonStyle())
                .accessibilityIdentifier("account.recovery.saved")
        }
        .interactiveDismissDisabled()
        .overlay {
            if scenePhase != .active {
                ZJTheme.pageBackground.ignoresSafeArea()
                    .overlay(Text("恢复资料已隐藏").font(.title3))
            }
        }
    }
}
