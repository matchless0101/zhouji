import SwiftData
import SwiftUI

struct TimerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(TimerController.self) private var timer
    @Query private var goals: [Goal]

    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                let ringDiameter = dynamicTypeSize.isAccessibilitySize
                    ? min(proxy.size.width * 0.9, max(230, proxy.size.height * 0.55))
                    : min(proxy.size.width * 0.76, max(150, (proxy.size.height - 180) * 0.67))
                let illustrationHeight = min(proxy.size.width * 0.5, max(60, proxy.size.height - 180 - ringDiameter))
                ScrollView {
                    VStack(spacing: 12) {
                        Text(timer.activeSession?.taskTitleSnapshot ?? "本次计时")
                            .font(ZJTheme.handwriting(32, relativeTo: .title).weight(.bold))
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 16)
                        if let goal = timer.activeSession?.goalNameSnapshot {
                            HStack(spacing: 8) {
                                ZJGoalIcon(iconName: goalIcon(for: goal), size: 32)
                                Text(goal)
                                    .font(ZJTheme.handwriting(20, relativeTo: .subheadline))
                                    .foregroundStyle(ZJTheme.secondaryInk)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .accessibilityIdentifier("timer.goal")
                            }
                        }
                        HStack(spacing: 9) {
                            Image(systemName: timer.isRunning ? "circle.fill" : "pause.fill")
                                .font(.system(size: 12))
                                .foregroundStyle(ZJTheme.success)
                                .accessibilityHidden(true)
                            Text(timer.isRunning ? "正在投入" : "已经暂停")
                                .font(ZJTheme.handwriting(20, relativeTo: .headline))
                        }
                        .padding(.top, 12)

                        TimerDial(diameter: ringDiameter)
                        if !dynamicTypeSize.isAccessibilitySize {
                            ZJIllustration(name: "LiuliTimer", height: illustrationHeight)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, ZJTheme.pagePadding)
                    .padding(.bottom, 8)
                }
            }
            .safeAreaInset(edge: .top, spacing: 0) { navigationHeader }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                VStack(spacing: 10) {
                    Button {
                        if timer.isRunning { _ = timer.pause() } else { _ = timer.resume() }
                    } label: {
                        Label(timer.isRunning ? "暂停" : "继续", systemImage: timer.isRunning ? "pause.fill" : "play.fill")
                    }
                    .buttonStyle(ZJPrintedButtonStyle())
                    Button {
                        if timer.finishActiveSession() { dismiss() }
                    } label: {
                        Label("结束计时", systemImage: "stop.fill")
                    }
                    .buttonStyle(ZJPaperButtonStyle(border: ZJTheme.divider))
                }
                .padding(.horizontal, ZJTheme.pagePadding)
                .padding(.top, 8)
                .padding(.bottom, 12)
                .background(ZJTheme.pageBackground)
            }
            .foregroundStyle(ZJTheme.ink)
            .background(ZJTheme.pageBackground.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
        }
        .presentationBackground(ZJTheme.background)
        .alert("计时未能保存", isPresented: Binding(
            get: { timer.errorMessage != nil },
            set: { if !$0 { timer.clearError() } }
        )) {
            Button("好", role: .cancel) { timer.clearError() }
        } message: {
            Text(timer.errorMessage ?? "请稍后重试。")
        }
    }

    private func goalIcon(for name: String) -> String {
        goals.first { $0.id == timer.activeSession?.goalIDSnapshot }?.displayIconName
            ?? GoalIcon.scope.resolved(for: name).rawValue
    }

    private var navigationHeader: some View {
        HStack(spacing: 6) {
            ZJBackButton(label: "返回", action: dismiss.callAsFunction)
            Text("计时")
                .font(ZJTheme.handwriting(28, relativeTo: .title).weight(.bold))
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 0)
            Button("收起", action: dismiss.callAsFunction)
                .font(ZJTheme.handwriting(19, relativeTo: .body))
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .foregroundStyle(ZJTheme.secondaryInk)
                .frame(minWidth: 44, minHeight: 44)
        }
        .padding(.horizontal, ZJTheme.pagePadding - 6)
        .padding(.top, 6)
        .background(ZJTheme.pageBackground)
    }
}

private struct TimerDial: View {
    @Environment(TimerController.self) private var timer
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .largeTitle) private var timerFontSize = 44.0
    let diameter: CGFloat

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let elapsedText = TimerMath.formattedDuration(timer.elapsed(at: context.date))
            ZStack {
                // A complete decorative ring, not a countdown or a fabricated progress value.
                Circle().strokeBorder(ZJTheme.success, lineWidth: 13)
                    .overlay {
                        ZJInkGrain(count: 2_000)
                            .mask(Circle().strokeBorder(lineWidth: 13))
                    }
                VStack(spacing: 8) {
                    Text(elapsedText)
                        .font(.system(size: timerFontSize, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .minimumScaleFactor(0.25)
                        .lineLimit(1)
                        .contentTransition(reduceMotion ? .identity : .numericText())
                    Text("本次投入")
                        .font(ZJTheme.handwriting(19, relativeTo: .caption))
                        .lineLimit(1)
                        .minimumScaleFactor(0.35)
                        .foregroundStyle(ZJTheme.secondaryInk)
                }
                .padding(24)
            }
            .frame(width: diameter, height: diameter)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("本次投入")
            .accessibilityValue(elapsedText)
            .accessibilityIdentifier("timer.elapsed")
        }
    }
}
