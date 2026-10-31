import SwiftUI

extension View {
    /// Asks in a bottom panel before replacing the running timer.
    func timerSwitchConfirmation(pendingTask: Binding<TodoTask?>, onConfirm: @escaping (TodoTask) -> Void) -> some View {
        modifier(TimerSwitchConfirmation(pendingTask: pendingTask, onConfirm: onConfirm))
    }
}

private struct TimerSwitchConfirmation: ViewModifier {
    @Binding var pendingTask: TodoTask?
    let onConfirm: (TodoTask) -> Void
    @State private var confirmedTask: TodoTask?

    func body(content: Content) -> some View {
        // Confirm after the panel is gone so a follow-up timer sheet can present cleanly.
        content.sheet(item: $pendingTask, onDismiss: {
            guard let task = confirmedTask else { return }
            confirmedTask = nil
            onConfirm(task)
        }) { task in
            TimerSwitchPanel(
                newTitle: task.title,
                onConfirm: {
                    confirmedTask = task
                    pendingTask = nil
                },
                onCancel: { pendingTask = nil }
            )
        }
    }
}

/// Shows what will be saved and what starts next, so the switch is understood before it happens.
private struct TimerSwitchPanel: View {
    @Environment(TimerController.self) private var timer
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let newTitle: String
    let onConfirm: () -> Void
    let onCancel: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("切换到新任务？")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(ZJTheme.ink)
                        .accessibilityAddTraits(.isHeader)
                    Text("同一时间只能计时一件事。确认后会先结束并保存当前计时，再开始新任务。")
                        .font(.subheadline)
                        .foregroundStyle(ZJTheme.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(spacing: 8) {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("正在计时 · 将保存")
                                .font(.caption)
                                .foregroundStyle(ZJTheme.secondaryOnEmphasis)
                            Text(timer.activeSession?.taskTitleSnapshot ?? "当前任务")
                                .font(.headline)
                                .lineLimit(2)
                        }
                        Spacer(minLength: 8)
                        TimelineView(.periodic(from: .now, by: 1)) { context in
                            Text(TimerMath.formattedDuration(timer.elapsed(at: context.date)))
                                .font(.system(.title3, design: ZJTheme.numberDesign, weight: .light))
                                .monospacedDigit()
                        }
                    }
                    .foregroundStyle(ZJTheme.onEmphasis)
                    .padding(.horizontal, 18)
                    .frame(maxWidth: .infinity, minHeight: 76)
                    .background(ZJTheme.emphasisSurface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .accessibilityElement(children: .combine)

                    Image(systemName: "arrow.down")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(ZJTheme.ink)
                        .frame(width: 32, height: 32)
                        .background(ZJTheme.surface, in: Circle())
                        .shadow(color: .black.opacity(0.12), radius: 6, x: 0, y: 2)
                        .padding(.vertical, -20)
                        .zIndex(1)
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("接下来开始")
                            .font(.caption)
                            .foregroundStyle(ZJTheme.secondaryInk)
                        Text(newTitle)
                            .font(.headline)
                            .foregroundStyle(ZJTheme.ink)
                            .lineLimit(2)
                    }
                    .padding(.horizontal, 18)
                    .frame(maxWidth: .infinity, minHeight: 76, alignment: .leading)
                    .background(ZJTheme.mutedSurface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .accessibilityElement(children: .combine)
                }

                VStack(spacing: 10) {
                    Button(action: onConfirm) {
                        Text("保存并开始新计时")
                            .font(.headline)
                            .foregroundStyle(ZJTheme.onAccent)
                            .frame(maxWidth: .infinity, minHeight: 54)
                            .background(ZJTheme.accent, in: Capsule())
                    }
                    .accessibilityIdentifier("timer.switch.confirm")
                    Button(action: onCancel) {
                        Text("继续原计时")
                            .font(.headline)
                            .foregroundStyle(ZJTheme.ink)
                            .frame(maxWidth: .infinity, minHeight: 54)
                            .background(ZJTheme.mutedSurface, in: Capsule())
                    }
                    .accessibilityIdentifier("timer.switch.cancel")
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 22)
            .padding(.top, 26)
            .padding(.bottom, 12)
        }
        .scrollBounceBehavior(.basedOnSize)
        .presentationDetents(dynamicTypeSize.isAccessibilitySize ? [.large] : [.height(500), .large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(36)
        .presentationBackground(ZJTheme.surface)
    }
}
