import SwiftUI

struct TaskRow: View {
    let task: TodoTask
    let isActivelyTimed: Bool
    var showsGoal = true
    let onToggleCompletion: () -> Void
    let onStartTimer: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onToggleCompletion) {
                ZStack {
                    Circle()
                        .stroke(
                            task.isCompleted ? ZJTheme.success : ZJTheme.secondaryInk,
                            lineWidth: 1.5
                        )
                        .frame(width: 25, height: 25)

                    if task.isCompleted {
                        Circle()
                            .fill(ZJTheme.success)
                            .frame(width: 25, height: 25)
                        Image(systemName: "checkmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(ZJTheme.surface)
                    }
                }
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(task.isCompleted ? "恢复任务" : "完成任务")
            .accessibilityHint(task.title)

            VStack(alignment: .leading, spacing: 3) {
                Text(task.title)
                    .font(.system(.body, design: .default, weight: .medium))
                    .foregroundStyle(task.isCompleted ? ZJTheme.secondaryInk : ZJTheme.ink)
                    .strikethrough(task.isCompleted, color: ZJTheme.secondaryInk)
                    .lineLimit(3)

                if showsGoal, let goal = task.goal, goal.deletedAt == nil {
                    HStack(spacing: 5) {
                        Circle()
                            .fill(ZJTheme.accent)
                            .frame(width: 6, height: 6)
                        Text(goal.name)
                            .lineLimit(1)
                    }
                    .font(.caption)
                    .foregroundStyle(ZJTheme.accent)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(ZJTheme.accentSoft, in: Capsule())
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if task.isCompleted {
                if let completedAt = task.completedAt {
                    Text(completedAt, style: .time)
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(ZJTheme.secondaryInk)
                }
            } else {
                Button(action: onStartTimer) {
                    if isActivelyTimed {
                        Label("计时中", systemImage: "waveform")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(ZJTheme.surface)
                            .padding(.horizontal, 12)
                            .frame(minHeight: 38)
                            .background(ZJTheme.accent, in: Capsule())
                    } else {
                        Image(systemName: "play.fill")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(ZJTheme.accent)
                            .frame(width: 38, height: 38)
                            .background(ZJTheme.accentSoft, in: Circle())
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isActivelyTimed ? "查看计时" : "开始计时")
                .accessibilityHint(task.title)
            }
        }
        .padding(.vertical, ZJTheme.rowVerticalPadding)
        .contentShape(Rectangle())
    }
}
