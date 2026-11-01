import SwiftData
import SwiftUI

struct TimerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(TimerController.self) private var timer
    @Query private var sessions: [TimingSession]

    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                // Large text grows the status pill and the stacked buttons, so the dial yields first.
                let ringDiameter = dynamicTypeSize.isAccessibilitySize
                    ? min(proxy.size.width * 0.8, max(160, proxy.size.height - 180))
                    : min(proxy.size.width * 0.8, max(150, proxy.size.height - 300))
                ScrollView {
                    VStack(spacing: 24) {
                        statusPill
                        TimerDial(diameter: ringDiameter)
                        facts
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, ZJTheme.pagePadding + 2)
                    .padding(.top, 14)
                    .padding(.bottom, 8)
                }
            }
            .safeAreaInset(edge: .top, spacing: 0) { navigationHeader }
            .safeAreaInset(edge: .bottom, spacing: 0) { controls }
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

    private var navigationHeader: some View {
        HStack(alignment: .center) {
            Button(action: dismiss.callAsFunction) {
                Image(systemName: "chevron.down")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(ZJTheme.ink)
                    .frame(width: 44, height: 44)
                    .background(ZJTheme.surface, in: Circle())
                    .compositingGroup()
                    .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 4)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("收起")
            Spacer(minLength: 12)
            VStack(alignment: .trailing, spacing: 2) {
                Text("计时")
                    .font(.headline.weight(.bold))
                    .accessibilityAddTraits(.isHeader)
                if let goal = timer.activeSession?.goalNameSnapshot {
                    Text(goal)
                        .font(.caption)
                        .foregroundStyle(ZJTheme.secondaryInk)
                        .lineLimit(1)
                        .accessibilityIdentifier("timer.goal")
                }
            }
        }
        .padding(.horizontal, ZJTheme.pagePadding + 2)
        .padding(.top, 10)
        .padding(.bottom, 4)
        .background(ZJTheme.pageBackground)
    }

    /// Running state on the left in black, the task snapshot on the right.
    private var statusPill: some View {
        HStack(spacing: 10) {
            HStack(spacing: 8) {
                Circle()
                    .fill(ZJTheme.onAccent)
                    .frame(width: 6, height: 6)
                    .opacity(timer.isRunning ? 1 : 0.4)
                    .accessibilityHidden(true)
                Text(timer.isRunning ? "正在投入" : "已经暂停")
                    .font(.subheadline.weight(.semibold))
            }
            .foregroundStyle(ZJTheme.onAccent)
            .padding(.horizontal, 16)
            .frame(minHeight: 40)
            .background(ZJTheme.accent, in: Capsule())

            Text(timer.activeSession?.taskTitleSnapshot ?? "本次计时")
                .font(.body.weight(.semibold))
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(4)
        .padding(.trailing, 10)
        .background(ZJTheme.surface, in: Capsule())
        .compositingGroup()
        .shadow(color: .black.opacity(0.05), radius: 10, x: 0, y: 4)
    }

    /// When this timing began and everything this task has received so far, both read from the facts.
    private var facts: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            HStack(alignment: .top) {
                fact(title: "开始于",
                     value: timer.activeSession?.startedAt.formatted(date: .omitted, time: .shortened) ?? "--",
                     alignment: .leading)
                Spacer(minLength: 12)
                fact(title: "本任务累计",
                     value: TimerMath.formattedDuration(taskTotal(at: context.date)),
                     alignment: .trailing)
            }
        }
    }

    private func fact(title: String, value: String, alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(ZJTheme.secondaryInk)
            Text(value)
                .font(.system(.title2, design: ZJTheme.numberDesign, weight: .regular))
                .monospacedDigit()
        }
        .accessibilityElement(children: .combine)
    }

    private func taskTotal(at date: Date) -> TimeInterval {
        guard let active = timer.activeSession else { return 0 }
        let earlier = sessions
            .filter { $0.taskID == active.taskID && $0.id != active.id && $0.state == .finished }
            .reduce(0) { $0 + $1.accumulatedSeconds }
        return earlier + timer.elapsed(at: date)
    }

    private var controls: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: 10))
            : AnyLayout(HStackLayout(spacing: 12))
        return VStack(spacing: 12) {
            layout {
                Button {
                    if timer.isRunning { _ = timer.pause() } else { _ = timer.resume() }
                } label: {
                    Label(timer.isRunning ? "暂停" : "继续", systemImage: timer.isRunning ? "pause.fill" : "play.fill")
                }
                .buttonStyle(ZJPrimaryButtonStyle())
                Button {
                    if timer.finishActiveSession() { dismiss() }
                } label: {
                    Label("结束计时", systemImage: "stop.fill")
                }
                .buttonStyle(ZJSecondaryButtonStyle())
            }
            Text("结束只保存投入，不会完成任务 · 暂停时长不计入")
                .font(.caption)
                .foregroundStyle(ZJTheme.secondaryInk)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, ZJTheme.pagePadding + 2)
        .padding(.top, 8)
        .padding(.bottom, 12)
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
                DialFace(diameter: diameter)
                VStack(spacing: 8) {
                    Text(elapsedText)
                        .font(.system(size: timerFontSize * 1.1, weight: .light, design: ZJTheme.numberDesign))
                        .monospacedDigit()
                        .minimumScaleFactor(0.25)
                        .lineLimit(1)
                        .contentTransition(reduceMotion ? .identity : .numericText())
                    Text("本次投入")
                        .font(ZJTheme.titleFont(19, relativeTo: .caption))
                        .lineLimit(1)
                        .minimumScaleFactor(0.35)
                        .foregroundStyle(ZJTheme.secondaryInk)
                }
                .padding(diameter * 0.18)
            }
            .frame(width: diameter, height: diameter)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("本次投入")
            .accessibilityValue(elapsedText)
            .accessibilityIdentifier("timer.elapsed")
        }
    }
}

/// Watch-face ticks around a raised white disc; decorative, never a countdown or fabricated progress.
private struct DialFace: View {
    let diameter: CGFloat

    var body: some View {
        let tickDiameter = diameter - 16
        let circumference = CGFloat.pi * tickDiameter
        ZStack {
            Circle()
                .stroke(ZJTheme.ink.opacity(0.7),
                        style: StrokeStyle(lineWidth: 10, dash: [1.3, circumference / 60 - 1.3]))
                .frame(width: tickDiameter, height: tickDiameter)
            Circle()
                .stroke(ZJTheme.ink, style: StrokeStyle(lineWidth: 16, dash: [2.2, circumference / 12 - 2.2]))
                .frame(width: tickDiameter, height: tickDiameter)
            Circle()
                .fill(ZJTheme.surface)
                .frame(width: diameter * 0.76, height: diameter * 0.76)
                .shadow(color: .black.opacity(0.10), radius: 24, x: 0, y: 12)
                .shadow(color: .black.opacity(0.05), radius: 4, x: 0, y: 2)
        }
        .frame(width: diameter, height: diameter)
        .accessibilityHidden(true)
    }
}
