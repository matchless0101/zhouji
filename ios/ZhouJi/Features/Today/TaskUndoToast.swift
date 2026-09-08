import SwiftUI

struct TaskUndoToast: View {
    let taskTitle: String
    let onUndo: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Text("已删除“\(taskTitle)”")
                .font(.subheadline)
                .foregroundStyle(ZJTheme.surface)
                .lineLimit(1)

            Spacer()

            Button("撤销", action: onUndo)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(ZJTheme.surface)
                .accessibilityHint("恢复刚刚删除的任务")
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 46)
        .background(ZJTheme.ink, in: RoundedRectangle(cornerRadius: ZJTheme.compactCornerRadius))
        .padding(.horizontal, ZJTheme.pagePadding)
        .padding(.vertical, 8)
    }
}
