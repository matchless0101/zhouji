import SwiftUI

struct TimerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(TimerController.self) private var timer

    var body: some View {
        NavigationStack {
            ZStack {
                ZJTheme.pageBackground.ignoresSafeArea()

                VStack(spacing: 0) {
                    Spacer(minLength: 30)

                    Text(timer.activeSession?.taskTitleSnapshot ?? "本次计时")
                        .font(.system(.title2, design: .default, weight: .semibold))
                        .foregroundStyle(ZJTheme.ink)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 28)

                    Label(
                        timer.isRunning ? "正在投入" : "已经暂停",
                        systemImage: timer.isRunning ? "circle.fill" : "pause.fill"
                    )
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(timer.isRunning ? ZJTheme.timerAccent : ZJTheme.secondaryInk)
                    .padding(.horizontal, 12)
                    .frame(minHeight: 32)
                    .background(ZJTheme.timerSoft, in: Capsule())
                    .padding(.top, 12)

                    TimerDial()
                        .padding(.top, 26)

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
                        .buttonStyle(.zjTimer)

                        Button {
                            if timer.finishActiveSession() {
                                dismiss()
                            }
                        } label: {
                            Label("结束计时", systemImage: "stop.fill")
                                .font(.headline)
                                .frame(maxWidth: .infinity, minHeight: ZJTheme.controlHeight)
                        }
                        .buttonStyle(.zjSecondary)
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

private struct TimerDial: View {
    @Environment(TimerController.self) private var timer
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @ScaledMetric(relativeTo: .largeTitle) private var timerFontSize = 48.0
    @ScaledMetric(relativeTo: .body) private var ringWidth = 10.0

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let elapsedText = TimerMath.formattedDuration(timer.elapsed(at: context.date))

            ZStack {
                Circle()
                    .fill(ZJTheme.surface)
                    .shadow(color: ZJTheme.ink.opacity(0.045), radius: 18, x: 0, y: 8)

                Circle()
                    .stroke(ZJTheme.timerSoft, lineWidth: ringWidth)

                Circle()
                    .trim(from: 0, to: timer.isRunning ? 0.78 : 0.22)
                    .stroke(
                        ZJTheme.timerAccent,
                        style: StrokeStyle(lineWidth: ringWidth, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))

                VStack(spacing: 8) {
                    Text(elapsedText)
                        .font(.system(size: timerFontSize, weight: .light, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(ZJTheme.ink)
                        .minimumScaleFactor(0.62)
                        .lineLimit(1)
                        .contentTransition(reduceMotion ? .identity : .numericText())

                    Text("本次投入")
                        .font(.caption)
                        .foregroundStyle(ZJTheme.secondaryInk)
                }
                .padding(28)
            }
            .containerRelativeFrame(.horizontal) { length, _ in
                min(length * 0.72, 310)
            }
            .aspectRatio(1, contentMode: .fit)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("本次投入")
            .accessibilityValue(elapsedText)
        }
    }
}
