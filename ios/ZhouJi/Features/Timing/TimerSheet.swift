import SwiftUI

struct TimerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(TimerController.self) private var timer
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        NavigationStack {
            ZStack {
                ZJTheme.background.ignoresSafeArea()

                VStack(spacing: 0) {
                    Spacer(minLength: 44)

                    Text(timer.activeSession?.taskTitleSnapshot ?? "本次计时")
                        .font(.system(.title2, design: .default, weight: .semibold))
                        .foregroundStyle(ZJTheme.ink)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 28)

                    Text(timer.isRunning ? "正在投入" : "已经暂停")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(ZJTheme.secondaryInk)
                        .padding(.top, 9)

                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        Text(TimerMath.formattedDuration(timer.elapsed(at: context.date)))
                            .font(.system(size: 52, weight: .light, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(ZJTheme.ink)
                            .contentTransition(reduceMotion ? .identity : .numericText())
                            .padding(.top, 28)
                            .accessibilityLabel("已计时 \(TimerMath.formattedDuration(timer.elapsed(at: context.date)))")
                    }

                    Spacer()

                    VStack(spacing: 12) {
                        Button {
                            if timer.isRunning {
                                _ = timer.pause()
                            } else {
                                _ = timer.resume()
                            }
                        } label: {
                            Label(
                                timer.isRunning ? "暂停" : "继续",
                                systemImage: timer.isRunning ? "pause.fill" : "play.fill"
                            )
                            .font(.headline)
                            .frame(maxWidth: .infinity, minHeight: ZJTheme.controlHeight)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(ZJTheme.surface)
                        .background(ZJTheme.accent, in: RoundedRectangle(cornerRadius: ZJTheme.cornerRadius))

                        Button {
                            if timer.finishActiveSession() {
                                dismiss()
                            }
                        } label: {
                            Text("结束计时")
                                .font(.headline)
                                .frame(maxWidth: .infinity, minHeight: ZJTheme.controlHeight)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(ZJTheme.ink)
                        .background(ZJTheme.surface, in: RoundedRectangle(cornerRadius: ZJTheme.cornerRadius))
                    }
                    .padding(.horizontal, ZJTheme.pagePadding)
                    .padding(.bottom, 24)
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("收起") {
                        dismiss()
                    }
                    .foregroundStyle(ZJTheme.secondaryInk)
                }
            }
        }
        .presentationBackground(ZJTheme.background)
        .alert(
            "计时未能保存",
            isPresented: Binding(
                get: { timer.errorMessage != nil },
                set: { if !$0 { timer.clearError() } }
            )
        ) {
            Button("好", role: .cancel) {
                timer.clearError()
            }
        } message: {
            Text(timer.errorMessage ?? "请稍后重试。")
        }
    }
}
