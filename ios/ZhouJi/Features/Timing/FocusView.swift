import SwiftData
import SwiftUI
import UIKit

struct FocusView: View {
    @Environment(TimerController.self) private var timer

    @Query(
        filter: #Predicate<TodoTask> { $0.deletedAt == nil },
        sort: \TodoTask.createdAt
    )
    private var visibleTasks: [TodoTask]

    @Query private var sessions: [TimingSession]
    @State private var presentedError: String?

    private var availableTasks: [TodoTask] {
        visibleTasks.filter { !$0.isCompleted }
    }

    var body: some View {
        NavigationStack {
            TimelineView(.periodic(from: .now, by: timer.isRunning ? 1 : 60)) { context in
                let statistics = StatisticsService.snapshot(
                    tasks: visibleTasks,
                    sessions: sessions,
                    now: context.date
                )

                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        focusHeader

                        if timer.activeSession != nil {
                            activeFocusCard(at: context.date)
                        } else {
                            taskSelection
                        }

                        todaySummary(statistics)
                    }
                    .padding(.horizontal, ZJTheme.pagePadding)
                    .padding(.top, 12)
                    .padding(.bottom, 44)
                }
            }
            .background(ZJTheme.pageBackground.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .alert(
                "操作未完成",
                isPresented: Binding(
                    get: { presentedError != nil || timer.errorMessage != nil },
                    set: { if !$0 { presentedError = nil; timer.clearError() } }
                )
            ) {
                Button("好", role: .cancel) {
                    presentedError = nil
                    timer.clearError()
                }
            } message: {
                Text(presentedError ?? timer.errorMessage ?? "请稍后重试。")
            }
        }
    }

    private var focusHeader: some View {
        HStack(alignment: .bottom, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text("专注")
                    .font(.largeTitle.weight(.bold))
                    .foregroundStyle(ZJTheme.ink)

                Text("一次只做一件事，\n专注让平凡的日子发光。")
                    .font(.subheadline)
                    .foregroundStyle(ZJTheme.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 4)

            if let illustration = UIImage(named: "TodayJourney") {
                Image(uiImage: illustration)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 126, height: 108)
                    .scaleEffect(1.08)
                    .blendMode(.multiply)
                    .compositingGroup()
                    .clipShape(.rect(cornerRadius: 22))
                    .accessibilityHidden(true)
            }
        }
    }

    private func activeFocusCard(at date: Date) -> some View {
        VStack(spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                Label(timer.isRunning ? "正在专注" : "专注已暂停", systemImage: timer.isRunning ? "circle" : "pause.circle")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(timer.isRunning ? ZJTheme.timerAccent : ZJTheme.secondaryInk)

                Text(timer.activeSession?.taskTitleSnapshot ?? "本次专注")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(ZJTheme.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if let goalName = timer.activeSession?.goalNameSnapshot {
                    Label(goalName, systemImage: "scope")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(ZJTheme.accent)
                        .padding(.horizontal, 10)
                        .frame(minHeight: 28)
                        .background(ZJTheme.accentSoft, in: Capsule())
                }
            }

            FocusDial(elapsed: timer.elapsed(at: date), isRunning: timer.isRunning)
                .accessibilityIdentifier("focus.timer")

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 28) {
                    focusControlButtons
                }

                VStack(spacing: 14) {
                    focusControlButtons
                }
            }
        }
        .padding(20)
        .zjCard()
    }

    @ViewBuilder
    private var focusControlButtons: some View {
        Button {
            let succeeded = timer.isRunning ? timer.pause() : timer.resume()
            if !succeeded { presentedError = timer.errorMessage }
        } label: {
            FocusControlLabel(
                title: timer.isRunning ? "暂停" : "继续",
                systemImage: timer.isRunning ? "pause.fill" : "play.fill",
                tint: ZJTheme.accent,
                softTint: ZJTheme.accentSoft
            )
        }
        .buttonStyle(.plain)

        Button {
            if !timer.finishActiveSession() {
                presentedError = timer.errorMessage
            }
        } label: {
            FocusControlLabel(
                title: "结束",
                systemImage: "stop.fill",
                tint: ZJTheme.timerAccent,
                softTint: ZJTheme.timerSoft
            )
        }
        .buttonStyle(.plain)
    }

    private var taskSelection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("选择一件事开始")
                .font(.title3.weight(.bold))
                .foregroundStyle(ZJTheme.ink)

            if availableTasks.isEmpty {
                ZJEmptyState(
                    title: "还没有待办任务",
                    message: "先到“今天”添加一件事，再回来开始专注。",
                    systemImage: "sparkles"
                )
                .padding(18)
                .zjCard()
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(availableTasks.prefix(5).enumerated()), id: \.element.id) { index, task in
                        Button {
                            start(task)
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: task.goal?.displayIconName ?? "checkmark.circle")
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundStyle(task.goal.map { ZJTheme.goalAccent(for: $0.displayIconName) } ?? ZJTheme.accent)
                                    .frame(width: 42, height: 42)
                                    .background(
                                        task.goal.map { ZJTheme.goalSoft(for: $0.displayIconName) } ?? ZJTheme.accentSoft,
                                        in: RoundedRectangle(cornerRadius: 13, style: .continuous)
                                    )

                                VStack(alignment: .leading, spacing: 3) {
                                    Text(task.title)
                                        .font(.body.weight(.semibold))
                                        .foregroundStyle(ZJTheme.ink)
                                        .lineLimit(2)

                                    Text(task.goal?.name ?? "未关联目标")
                                        .font(.caption)
                                        .foregroundStyle(ZJTheme.secondaryInk)
                                        .lineLimit(1)
                                }

                                Spacer(minLength: 8)

                                Image(systemName: "play.fill")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(ZJTheme.timerAccent)
                                    .frame(width: 38, height: 38)
                                    .background(ZJTheme.timerSoft, in: Circle())
                            }
                            .padding(.horizontal, 14)
                            .frame(minHeight: 68)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("开始专注，\(task.title)")

                        if index < min(availableTasks.count, 5) - 1 {
                            Divider()
                                .overlay(ZJTheme.divider)
                                .padding(.leading, 68)
                        }
                    }
                }
                .zjCard()
            }
        }
    }

    private func todaySummary(_ statistics: StatisticsSnapshot) -> some View {
        HStack(spacing: 0) {
            FocusMetric(
                title: "今日专注时长",
                value: ElapsedTimeText.string(for: statistics.secondsToday),
                systemImage: "clock"
            )

            Divider()
                .overlay(ZJTheme.divider)
                .frame(height: 58)

            FocusMetric(
                title: "今日完成次数",
                value: "\(statistics.completedToday) 次",
                systemImage: "scope"
            )
        }
        .padding(.vertical, 16)
        .zjCard()
    }

    private func start(_ task: TodoTask) {
        switch timer.requestStart(for: task) {
        case .started, .showCurrent:
            break
        case .confirmSwitch:
            presentedError = "请先结束当前专注，再开始新的任务。"
        case .failed:
            presentedError = timer.errorMessage
        }
    }
}

private struct FocusDial: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .largeTitle) private var timerFontSize = 45.0
    @ScaledMetric(relativeTo: .body) private var ringWidth = 9.0

    let elapsed: TimeInterval
    let isRunning: Bool

    var body: some View {
        ZStack {
            Circle()
                .fill(ZJTheme.surface)
                .shadow(color: ZJTheme.accent.opacity(0.10), radius: 18, x: 0, y: 8)

            Circle()
                .stroke(ZJTheme.accentSoft, lineWidth: ringWidth)

            Circle()
                .trim(from: 0.03, to: isRunning ? 0.86 : 0.34)
                .stroke(
                    ZJTheme.accent,
                    style: StrokeStyle(lineWidth: ringWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))

            VStack(spacing: 8) {
                Image(systemName: "leaf.fill")
                    .font(.title3)
                    .foregroundStyle(ZJTheme.success)

                Text(TimerMath.formattedDuration(elapsed))
                    .font(.system(size: timerFontSize, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(ZJTheme.ink)
                    .minimumScaleFactor(0.62)
                    .lineLimit(1)
                    .contentTransition(reduceMotion ? .identity : .numericText())

                Text(isRunning ? "专注中 · 保持专注" : "已暂停 · 随时继续")
                    .font(.caption)
                    .foregroundStyle(ZJTheme.secondaryInk)
            }
            .padding(26)
        }
        .frame(maxWidth: 270)
        .aspectRatio(1, contentMode: .fit)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(isRunning ? "正在专注" : "专注已暂停")
        .accessibilityValue(TimerMath.formattedDuration(elapsed))
    }
}

private struct FocusControlLabel: View {
    let title: String
    let systemImage: String
    let tint: Color
    let softTint: Color

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 64, height: 64)
                .background(softTint, in: Circle())
                .overlay { Circle().stroke(.white.opacity(0.68), lineWidth: 1) }
                .shadow(color: tint.opacity(0.14), radius: 12, x: 0, y: 5)

            Text(title)
                .font(.subheadline)
                .foregroundStyle(ZJTheme.secondaryInk)
        }
        .frame(minWidth: 84)
    }
}

private struct FocusMetric: View {
    let title: String
    let value: String
    let systemImage: String

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Label(title, systemImage: systemImage)
                .font(.caption)
                .foregroundStyle(ZJTheme.secondaryInk)
                .lineLimit(1)

            Text(value)
                .font(.title3.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(ZJTheme.ink)
                .minimumScaleFactor(0.72)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
    }
}

#Preview {
    FocusView()
        .environment(TimerController())
        .modelContainer(for: [Goal.self, TodoTask.self, TimingSession.self], inMemory: true)
}
