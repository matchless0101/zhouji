import SwiftUI

/// A black capsule with the seconds left to undo; it is recreated for every deletion.
struct TaskUndoToast: View {
    let taskTitle: String
    let onUndo: () -> Void
    @State private var deletedAt = Date.now

    var body: some View {
        HStack(spacing: 10) {
            Text("已删除「\(taskTitle)」")
                .font(.subheadline)
                .foregroundStyle(ZJTheme.onEmphasis)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            TimelineView(.periodic(from: deletedAt, by: 1)) { context in
                let remaining = max(0, 5 - Int(context.date.timeIntervalSince(deletedAt)))
                Text("\(remaining)s")
                    .font(.caption.weight(.medium))
                    .monospacedDigit()
                    .foregroundStyle(ZJTheme.secondaryOnEmphasis)
                    .accessibilityHidden(true)
            }

            Button(action: onUndo) {
                Text("撤销")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(ZJTheme.ink)
                    .padding(.horizontal, 16)
                    .frame(minHeight: 40)
                    .background(ZJTheme.onEmphasis, in: Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("撤销")
            .accessibilityHint("恢复刚刚删除的任务")
        }
        .padding(.leading, 18)
        .padding(.trailing, 6)
        .frame(minHeight: 52)
        .background(ZJTheme.emphasisSurface, in: Capsule())
        .compositingGroup()
        .shadow(color: .black.opacity(0.22), radius: 14, x: 0, y: 6)
        .padding(.horizontal, ZJTheme.pagePadding)
    }
}
