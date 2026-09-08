import SwiftData
import SwiftUI

struct RecordsView: View {
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
                let goalIcons = goals.reduce(into: [UUID: GoalIcon]()) { result, goal in
                    result[goal.id] = goal.icon
                }

                RecordsContent(
                    date: context.date,
                    statistics: statistics,
                    goalIcons: goalIcons
                )
            }
            .toolbar(.hidden, for: .navigationBar)
            .background(ZJTheme.background.ignoresSafeArea())
        }
    }
}

private struct RecordsContent: View {
    let date: Date
    let statistics: StatisticsSnapshot
    let goalIcons: [UUID: GoalIcon]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                RecordsHeader()

                RecordsPeriodSection(
                    title: "今天",
                    dateText: Self.dayText(for: date),
                    completed: statistics.completedToday,
                    seconds: statistics.secondsToday,
                    identifier: "today"
                )

                RecordsPeriodSection(
                    title: "本周",
                    dateText: Self.weekText(for: date),
                    completed: statistics.completedThisWeek,
                    seconds: statistics.secondsThisWeek,
                    identifier: "week"
                )

                RecordsGoalSection(
                    summaries: statistics.goalTimesThisWeek,
                    goalIcons: goalIcons
                )
            }
            .padding(.horizontal, ZJTheme.pagePadding)
            .padding(.top, 12)
            .padding(.bottom, 44)
        }
        .background(ZJTheme.background)
    }

    @MainActor
    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日 EEE"
        return formatter
    }()

    @MainActor
    private static let shortDayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日"
        return formatter
    }()

    private static func dayText(for date: Date) -> String {
        dayFormatter.string(from: date)
    }

    private static func weekText(for date: Date) -> String {
        let week = DateBoundaries.mondayWeek(containing: date)
        let inclusiveEnd = week.end.addingTimeInterval(-1)
        return "\(shortDayFormatter.string(from: week.start)) 至 \(shortDayFormatter.string(from: inclusiveEnd))"
    }
}

private struct RecordsHeader: View {
    var body: some View {
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
}

private struct RecordsPeriodSection: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let title: String
    let dateText: String
    let completed: Int
    let seconds: TimeInterval
    let identifier: String

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(title)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(ZJTheme.ink)

                Text(dateText)
                    .font(.subheadline)
                    .foregroundStyle(ZJTheme.secondaryInk)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }

            if dynamicTypeSize.isAccessibilitySize {
                VStack(spacing: 12) {
                    completedCard
                    durationCard
                }
            } else {
                HStack(alignment: .top, spacing: 12) {
                    completedCard
                    durationCard
                }
            }
        }
    }

    private var completedCard: some View {
        RecordsMetricCard(
            title: "完成任务数",
            value: "\(completed) 件",
            symbol: "checkmark",
            identifier: "records.\(identifier).completed"
        )
    }

    private var durationCard: some View {
        RecordsMetricCard(
            title: "有效计时时长",
            value: ElapsedTimeText.string(for: seconds),
            symbol: "clock",
            identifier: "records.\(identifier).duration"
        )
    }
}

private struct RecordsMetricCard: View {
    let title: String
    let value: String
    let symbol: String
    let identifier: String

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label {
                Text(title)
                    .font(.subheadline)
                    .foregroundStyle(ZJTheme.secondaryInk)
            } icon: {
                Image(systemName: symbol)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(ZJTheme.surface)
                    .frame(width: 24, height: 24)
                    .background(ZJTheme.accent.opacity(0.72), in: Circle())
            }

            Text(value)
                .font(.system(.title2, design: .rounded, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(ZJTheme.ink)
                .minimumScaleFactor(0.76)
                .lineLimit(1)
                .accessibilityIdentifier(identifier)
        }
        .frame(maxWidth: .infinity, minHeight: 112, alignment: .topLeading)
        .padding(16)
        .zjCard()
    }
}

private struct RecordsGoalSection: View {
    let summaries: [GoalTimeSummary]
    let goalIcons: [UUID: GoalIcon]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    sectionTitle
                    sectionDescription
                }

                VStack(alignment: .leading, spacing: 5) {
                    sectionTitle
                    sectionDescription
                }
            }

            if summaries.isEmpty {
                ZJEmptyState(
                    title: "还没有目标投入",
                    message: "为目标任务结束一次计时后，会在这里留下记录。",
                    systemImage: "clock.arrow.circlepath"
                )
                .padding(18)
                .zjCard()
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(summaries.enumerated()), id: \.element.id) { index, summary in
                        GoalTimeRow(
                            summary: summary,
                            icon: goalIcons[summary.id] ?? .scope
                        )

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

    private var sectionTitle: some View {
        Text("目标投入")
            .font(.title3.weight(.bold))
            .foregroundStyle(ZJTheme.ink)
    }

    private var sectionDescription: some View {
        Text("本周各目标的有效计时时长")
            .font(.caption)
            .foregroundStyle(ZJTheme.secondaryInk)
    }
}

private struct GoalTimeRow: View {
    let summary: GoalTimeSummary
    let icon: GoalIcon

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon.rawValue)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(ZJTheme.accent)
                .frame(width: 36, height: 36)
                .background(
                    ZJTheme.accentSoft,
                    in: RoundedRectangle(cornerRadius: 11, style: .continuous)
                )
                .accessibilityHidden(true)

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
    }
}
