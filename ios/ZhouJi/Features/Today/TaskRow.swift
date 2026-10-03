import SwiftUI

struct TaskRow: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .body) private var completionSize = 28.0
    @State private var isCompleting = false

    let task: TodoTask
    let isActivelyTimed: Bool
    var showsGoal = true
    var presentation: Presentation = .standard
    var animatesCompletion = false
    let onToggleCompletion: () -> Void
    let onStartTimer: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: toggleCompletion) {
                ZStack {
                    Circle()
                        .stroke(
                            task.isCompleted || isCompleting ? ZJTheme.success : ZJTheme.secondaryInk,
                            lineWidth: 1.5
                        )
                        .frame(width: completionSize, height: completionSize)

                    if task.isCompleted || isCompleting {
                        Circle()
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
                    .strikethrough(presentation == .goal && task.isCompleted, color: ZJTheme.secondaryInk)
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
                if presentation == .standard, let completedAt = task.completedAt {
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
                    } else if presentation == .goal {
                        Image(systemName: "play.fill")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(ZJTheme.success)
                            .frame(width: 44, height: 44)
                    } else {
                        Image(systemName: "play.fill")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(ZJTheme.timerAccent)
                            .frame(width: 44, height: 44)
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
                .disabled(isCompleting)
                .accessibilityLabel(isActivelyTimed ? "查看计时" : "开始计时")
                .accessibilityHint(task.title)
            }
        }
        .padding(.vertical, presentation == .goal ? 0 : (task.isCompleted ? 0 : 10))
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
            withAnimation(.easeOut(duration: 0.28)) {
                isCompleting = false
                onToggleCompletion()
            }
        }
    }

    enum Presentation {
        case standard
        case goal
    }
}
