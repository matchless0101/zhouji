import SwiftData
import SwiftUI

struct RecordsView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Query private var tasks: [TodoTask]
    @Query private var sessions: [TimingSession]
    @Query private var goals: [Goal]

    private var refreshInterval: TimeInterval {
        sessions.contains { $0.state == .running } ? 1 : 60
    }

    var body: some View {
        NavigationStack {
            TimelineView(.periodic(from: .now, by: refreshInterval)) { context in
                let statistics = StatisticsService.snapshot(
                    tasks: tasks,
                    sessions: sessions,
                    now: context.date
                )

                ScrollView {
                    VStack(alignment: .leading, spacing: 28) {
                        pageHeader

                        periodSection(
                            title: "今天",
                            dateText: dayText(for: context.date),
                            completed: statistics.completedToday,
                            seconds: statistics.secondsToday,
                            identifier: "today"
                        )

                        periodSection(
                            title: "本周",
                            dateText: weekText(for: context.date),
                            completed: statistics.completedThisWeek,
                            seconds: statistics.secondsThisWeek,
                            identifier: "week"
                        )

                        goalSection(statistics.goalTimesThisWeek)
                    }
                    .padding(.horizontal, ZJTheme.pagePadding)
                    .padding(.top, 12)
                    .padding(.bottom, 44)
                }
                .background(ZJTheme.background)
            }
            .toolbar(.hidden, for: .navigationBar)
            .background(ZJTheme.background.ignoresSafeArea())
        }
    }

    private var pageHeader: some View {
        VStack(alignment: .leading, spacing: 24) {
            ZJBrandHeader(
                subtitle: "记录每一份投入，看见持续的进步。",
                systemImage: "chart.bar.xaxis"
            )

            Text("记录")
                .font(.system(.largeTitle, design: .rounded, weight: .bold))
                .foregroundStyle(ZJTheme.ink)
        }
    }

    private func periodSection(
        title: String,
        dateText: String,
        completed: Int,
        seconds: TimeInterval,
        identifier: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(title)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(ZJTheme.ink)
                Text(dateText)
                    .font(.subheadline)
                    .foregroundStyle(ZJTheme.secondaryInk)
            }

            if dynamicTypeSize.isAccessibilitySize {
                VStack(spacing: 12) {
                    completedCard(completed, identifier: identifier)
                    durationCard(seconds, identifier: identifier)
                }
            } else {
                HStack(alignment: .top, spacing: 12) {
                    completedCard(completed, identifier: identifier)
                    durationCard(seconds, identifier: identifier)
                }
            }
        }
    }

    private func completedCard(_ completed: Int, identifier: String) -> some View {
        metricCard(
            title: "完成任务数",
            symbol: "checkmark",
            identifier: "records.\(identifier).completed"
        ) {
            Text("\(completed) 件")
                .font(.system(.title, design: .rounded, weight: .bold))
                .monospacedDigit()
        }
    }

    private func durationCard(_ seconds: TimeInterval, identifier: String) -> some View {
        metricCard(
            title: "有效计时时长",
            symbol: "clock",
            identifier: "records.\(identifier).duration"
        ) {
            Text(ElapsedTimeText.string(for: seconds))
                .font(.system(.title3, design: .rounded, weight: .bold))
                .monospacedDigit()
                .minimumScaleFactor(0.78)
                .lineLimit(1)
        }
    }

    private func metricCard<Content: View>(
        title: String,
        symbol: String,
        identifier: String,
        @ViewBuilder value: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            Label {
                Text(title)
                    .font(.subheadline)
                    .foregroundStyle(ZJTheme.secondaryInk)
            } icon: {
                Image(systemName: symbol)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(ZJTheme.surface)
                    .frame(width: 22, height: 22)
                    .background(ZJTheme.accent.opacity(0.72), in: Circle())
            }

            value()
                .foregroundStyle(ZJTheme.ink)
                .accessibilityIdentifier(identifier)
        }
        .frame(maxWidth: .infinity, minHeight: 112, alignment: .topLeading)
        .padding(16)
        .zjCard()
    }

    @ViewBuilder
    private func goalSection(_ summaries: [GoalTimeSummary]) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("目标投入")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(ZJTheme.ink)
                Text("本周各目标的有效计时时长")
                    .font(.caption)
                    .foregroundStyle(ZJTheme.secondaryInk)
            }

            if summaries.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("还没有目标投入")
                        .font(.headline)
                        .foregroundStyle(ZJTheme.ink)
                    Text("为目标任务结束一次计时后，会在这里留下记录。")
                        .font(.subheadline)
                        .foregroundStyle(ZJTheme.secondaryInk)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(18)
                .zjCard()
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(summaries.enumerated()), id: \.element.id) { index, summary in
                        HStack(spacing: 12) {
                            Image(systemName: goalIcon(for: summary.id).rawValue)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(ZJTheme.accent)
                                .frame(width: 36, height: 36)
                                .background(ZJTheme.accentSoft, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                                .accessibilityLabel("目标图标，\(goalIcon(for: summary.id).title)")

                            Text(summary.name)
                                .font(.body.weight(.medium))
                                .foregroundStyle(ZJTheme.ink)
                                .lineLimit(2)

                            Spacer(minLength: 12)

                            Text(ElapsedTimeText.string(for: summary.seconds))
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(ZJTheme.ink)
                                .monospacedDigit()
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("\(summary.name)，本周投入 \(ElapsedTimeText.string(for: summary.seconds))")

                        if index < summaries.count - 1 {
                            Divider()
                                .overlay(ZJTheme.divider)
                                .padding(.leading, 64)
                        }
                    }
                }
                .zjCard()
            }
        }
    }

    private func dayText(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日 EEE"
        return formatter.string(from: date)
    }

    private func weekText(for date: Date) -> String {
        let week = DateBoundaries.mondayWeek(containing: date)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日"
        let inclusiveEnd = week.end.addingTimeInterval(-1)
        return "\(formatter.string(from: week.start)) 至 \(formatter.string(from: inclusiveEnd))"
    }

    private func goalIcon(for id: UUID) -> GoalIcon {
        goals.first { $0.id == id }?.icon ?? .scope
    }
}
