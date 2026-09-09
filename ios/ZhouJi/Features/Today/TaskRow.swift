import SwiftUI

struct TaskRow: View {
    @ScaledMetric(relativeTo: .body) private var completionSize = 28.0

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
                        .frame(width: completionSize, height: completionSize)

                    if task.isCompleted {
                        Circle()
                            .fill(ZJTheme.success)
                            .frame(width: completionSize, height: completionSize)
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
                    .lineLimit(3)

                if showsGoal, !task.isCompleted, let goal = task.goal, goal.deletedAt == nil {
                    let goalColor = ZJTheme.goalAccent(for: goal.displayIconName)

                    HStack(spacing: 5) {
                        Circle()
                            .fill(goalColor)
                            .frame(width: 6, height: 6)
                        Text(goal.name)
                            .lineLimit(1)
                    }
                    .font(.caption)
                    .foregroundStyle(goalColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(ZJTheme.goalSoft(for: goal.displayIconName), in: Capsule())
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if task.isCompleted {
                if let completedAt = task.completedAt {
                    Text(completedAt, style: .time)
                        .font(.subheadline)
                        .monospacedDigit()
                        .foregroundStyle(ZJTheme.secondaryInk)
                }
            } else {
                Button(action: onStartTimer) {
                    if isActivelyTimed {
                        Label("计时中", systemImage: "waveform")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(ZJTheme.surface)
                            .padding(.horizontal, 16)
                            .frame(minHeight: 44)
                            .background(ZJTheme.timerAccent, in: Capsule())
                    } else {
                        Label("开始", systemImage: "play.fill")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(ZJTheme.timerAccent)
                            .padding(.horizontal, 16)
                            .frame(minHeight: 44)
                            .background(
                                LinearGradient(colors: [ZJTheme.timerSoft.opacity(0.65), ZJTheme.timerSoft],
                                               startPoint: .topLeading, endPoint: .bottomTrailing),
                                in: Capsule()
                            )
                            .overlay { Capsule().stroke(ZJTheme.surface, lineWidth: 1.5) }
                            .shadow(color: ZJTheme.timerAccent.opacity(0.10), radius: 8, y: 3)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isActivelyTimed ? "查看计时" : "开始计时")
                .accessibilityHint(task.title)
            }
        }
        .padding(.vertical, task.isCompleted ? 0 : 10)
        .contentShape(Rectangle())
    }
}
