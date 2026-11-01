import SwiftUI

struct TaskRow: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .body) private var completionSize = 28.0
    @State private var isCompleting = false

    let task: TodoTask
    let isActivelyTimed: Bool
    var showsGoal = true
    var animatesCompletion = false
    let onToggleCompletion: () -> Void
    let onStartTimer: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: toggleCompletion) {
                // Soft squares mark completion.
                let markShape = RoundedRectangle(cornerRadius: completionSize * 0.28, style: .continuous)
                ZStack {
                    markShape
                        .stroke(
                            task.isCompleted || isCompleting ? ZJTheme.success : ZJTheme.secondaryInk,
                            lineWidth: 1.5
                        )
                        .frame(width: completionSize, height: completionSize)

                    if task.isCompleted || isCompleting {
                        markShape
                            .fill(ZJTheme.success)
                            .frame(width: completionSize, height: completionSize)
                        Image(systemName: "checkmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(ZJTheme.surface)
                    }
                }
                .scaleEffect(isCompleting ? 0.88 : 1)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(isCompleting)
            .accessibilityLabel(task.isCompleted ? "恢复任务" : "完成任务")
            .accessibilityHint(task.title)

            VStack(alignment: .leading, spacing: 3) {
                Text(task.title)
                    .font(.system(.body, design: .default, weight: .medium))
                    .foregroundStyle(task.isCompleted ? ZJTheme.secondaryInk : ZJTheme.ink)
                    .lineLimit(3)

                if showsGoal, !task.isCompleted, let goal = task.goal, goal.deletedAt == nil {
                    Text(isActivelyTimed ? "\(goal.name) · 计时中" : goal.name)
                        .font(.caption)
                        .foregroundStyle(ZJTheme.secondaryInk)
                        .lineLimit(1)
                } else if isActivelyTimed {
                    Text("计时中")
                        .font(.caption)
                        .foregroundStyle(ZJTheme.secondaryInk)
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
                        Image(systemName: "waveform")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(ZJTheme.onAccent)
                            .frame(width: 40, height: 40)
                            .background(ZJTheme.accent, in: Circle())
                            .frame(width: 44, height: 44)
                    } else {
                        Image(systemName: "play.fill")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(ZJTheme.ink)
                            .frame(width: 40, height: 40)
                            .background(ZJTheme.mutedSurface, in: Circle())
                            .frame(width: 44, height: 44)
                    }
                }
                .buttonStyle(.plain)
                .disabled(isCompleting)
                .accessibilityLabel(isActivelyTimed ? "查看计时" : "开始计时")
                .accessibilityHint(task.title)
            }
        }
        .padding(.vertical, task.isCompleted ? 0 : 10)
        .contentShape(Rectangle())
    }

    private func toggleCompletion() {
        guard animatesCompletion, !reduceMotion, !task.isCompleted else {
            onToggleCompletion()
            return
        }
        // Keep the checked circle visible briefly before its row changes sections.
        withAnimation(.easeOut(duration: 0.12), completionCriteria: .logicallyComplete) {
            isCompleting = true
        } completion: {
            withAnimation(.spring(duration: 0.45, bounce: 0.12)) {
                isCompleting = false
                onToggleCompletion()
            }
        }
    }
}
