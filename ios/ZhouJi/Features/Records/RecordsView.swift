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
                let calendar = Calendar.current
                let yesterday = calendar.date(byAdding: .day, value: -1, to: context.date) ?? context.date
                let lastWeek = calendar.date(byAdding: .day, value: -7, to: context.date) ?? context.date
                RecordsContent(
                    date: context.date,
                    statistics: StatisticsService.snapshot(tasks: tasks, sessions: sessions, now: context.date),
                    yesterday: StatisticsService.snapshot(tasks: tasks, sessions: sessions, now: context.date, periodDate: yesterday),
                    lastWeek: StatisticsService.snapshot(tasks: tasks, sessions: sessions, now: context.date, periodDate: lastWeek),
                    goals: goals
                )
            }
            .toolbar(.hidden, for: .navigationBar)
            .background(ZJTheme.pageBackground.ignoresSafeArea())
        }
    }
}

private enum RecordsPeriod: String, CaseIterable, Identifiable {
    case today, week
    var id: String { rawValue }
    var title: String { self == .today ? "今天" : "本周" }
}

private struct RecordsContent: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selectedPeriod = RecordsPeriod.today

    let date: Date
    let statistics: StatisticsSnapshot
    let yesterday: StatisticsSnapshot
    let lastWeek: StatisticsSnapshot
    let goals: [Goal]

    var body: some View {
        ScrollViewReader { proxy in
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("记录")
                        .font(.largeTitle.weight(.bold))
                        .foregroundStyle(ZJTheme.ink)
                        .padding(.leading, 4)

                    HStack(spacing: 2) {
                        ForEach(RecordsPeriod.allCases) { period in
                            Button {
                                selectedPeriod = period
                                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) {
                                    proxy.scrollTo(period, anchor: .top)
                                }
                            } label: {
                                Text(period.title)
                                    .font(.body.weight(selectedPeriod == period ? .medium : .regular))
                                    .foregroundStyle(selectedPeriod == period ? ZJTheme.ink : ZJTheme.secondaryInk)
                                    .frame(maxWidth: .infinity, minHeight: 44)
                                    .background(selectedPeriod == period ? ZJTheme.surface : .clear, in: Capsule())
                                    .shadow(color: selectedPeriod == period ? ZJTheme.secondaryInk.opacity(0.08) : .clear,
                                            radius: 6, y: 3)
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("records.period.\(period.rawValue)")
                            .accessibilityAddTraits(selectedPeriod == period ? .isSelected : [])
                        }
                    }
                    .padding(2)
                    .background(ZJTheme.mutedSurface.opacity(0.8), in: Capsule())
                    .accessibilityElement(children: .contain)
                    .accessibilityLabel("记录时间范围")
                }
                .padding(.top, ZJTheme.pageTopSpacing)

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        RecordsPeriodSection(
                            title: "今天", dateText: Self.dayFormatter.string(from: date),
                            completed: statistics.completedToday, seconds: statistics.secondsToday,
                            completedDetail: StatisticsComparison.completed(statistics.completedToday, previous: yesterday.completedToday, period: "昨天"),
                            durationDetail: "专注让平凡的日子发光", identifier: "today"
                        )
                        .id(RecordsPeriod.today)

                        RecordsPeriodSection(
                            title: "本周", dateText: Self.weekText(for: date),
                            completed: statistics.completedThisWeek, seconds: statistics.secondsThisWeek,
                            completedDetail: StatisticsComparison.completed(statistics.completedThisWeek, previous: lastWeek.completedThisWeek, period: "上周"),
                            durationDetail: StatisticsComparison.duration(statistics.secondsThisWeek, previous: lastWeek.secondsThisWeek, period: "上周"),
                            identifier: "week"
                        )
                        .id(RecordsPeriod.week)

                        RecordsGoalSection(summaries: statistics.goalTimesThisWeek, goals: goals)
                    }
                    .padding(.bottom, 16)
                }
                .scrollIndicators(.hidden)
            }
            .padding(.horizontal, ZJTheme.pagePadding)
        }
    }

    @MainActor
    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日  EEE"
        return formatter
    }()

    @MainActor
    private static let shortDayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日"
        return formatter
    }()

    private static func weekText(for date: Date) -> String {
        let week = DateBoundaries.mondayWeek(containing: date)
        return "\(shortDayFormatter.string(from: week.start)) - \(shortDayFormatter.string(from: week.end.addingTimeInterval(-1)))"
    }
}

private struct RecordsPeriodSection: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let title: String
    let dateText: String
    let completed: Int
    let seconds: TimeInterval
    let completedDetail: String
    let durationDetail: String
    let identifier: String

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: 10) { heading; dateLabel }
                VStack(alignment: .leading, spacing: 4) { heading; dateLabel }
            }

            let layout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(spacing: 10))
                : AnyLayout(HStackLayout(alignment: .top, spacing: 10))
            layout {
                RecordsMetricCard(title: "完成任务数", value: "\(completed) 件",
                                  detail: completedDetail, isDuration: false,
                                  identifier: "records.\(identifier).completed")
                RecordsMetricCard(title: "有效计时时长", value: ElapsedTimeText.string(for: seconds),
                                  detail: durationDetail, isDuration: true,
                                  identifier: "records.\(identifier).duration")
            }
        }
    }

    private var heading: some View {
        Text(title).font(.title2.weight(.bold)).foregroundStyle(ZJTheme.ink)
    }
    private var dateLabel: some View {
        Text(dateText).font(.footnote).foregroundStyle(ZJTheme.secondaryInk)
    }
}

private struct RecordsMetricCard: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .largeTitle) private var numberSize = 34.0
    @ScaledMetric(relativeTo: .body) private var unitSize = 16.0
    let title: String
    let value: String
    let detail: String
    let isDuration: Bool
    let identifier: String

    private var formattedValue: AttributedString {
        var result = AttributedString()
        for character in value {
            var part = AttributedString(String(character))
            part.font = .system(size: character.isNumber ? numberSize : unitSize, weight: .semibold)
            result.append(part)
        }
        return result
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: isDuration ? "clock" : "checkmark")
                    .font(.system(size: isDuration ? 24 : 13, weight: .medium))
                    .foregroundStyle(isDuration ? ZJTheme.timerAccent : ZJTheme.surface)
                    .frame(width: 26, height: 26)
                    .background {
                        if !isDuration {
                            Circle()
                                .fill(LinearGradient(colors: [ZJTheme.timerSoft, ZJTheme.timerAccent],
                                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                                .overlay { Circle().stroke(ZJTheme.surface, lineWidth: 1.5) }
                                .shadow(color: ZJTheme.timerAccent.opacity(0.2), radius: 5, y: 2)
                        }
                    }
                    .accessibilityHidden(true)
                Text(title)
                    .font(.footnote)
                    .foregroundStyle(ZJTheme.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text(formattedValue)
                .monospacedDigit()
                .foregroundStyle(ZJTheme.ink)
                .minimumScaleFactor(0.65)
                .lineLimit(1)
                .accessibilityLabel(value)
                .accessibilityIdentifier(identifier)

            Text(detail)
                .font(.footnote)
                .foregroundStyle(ZJTheme.secondaryInk)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, minHeight: 90, alignment: .topLeading)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .zjCard()
    }
}

private struct RecordsGoalSection: View {
    let summaries: [GoalTimeSummary]
    let goals: [Goal]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: 10) { sectionTitle; sectionDescription }
                VStack(alignment: .leading, spacing: 4) { sectionTitle; sectionDescription }
            }
            .padding(.bottom, 2)

            if summaries.isEmpty {
                Text("为目标任务记录一次投入后，会显示在这里。")
                    .font(.subheadline)
                    .foregroundStyle(ZJTheme.secondaryInk)
                    .padding(.vertical, 16)
            } else {
                ForEach(summaries) { summary in
                    let goal = goals.first { $0.id == summary.id }
                    if let goal, goal.deletedAt == nil {
                        NavigationLink {
                            GoalDetailView(goal: goal)
                        } label: {
                            GoalTimeRow(summary: summary, icon: goal.icon, showsChevron: true)
                        }
                        .buttonStyle(.plain)
                    } else {
                        GoalTimeRow(summary: summary, icon: goal?.icon ?? .general, showsChevron: false)
                    }
                    if summary.id != summaries.last?.id {
                        Divider().overlay(ZJTheme.divider.opacity(0.5)).padding(.leading, 46)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .zjCard()
    }

    private var sectionTitle: some View {
        Text("目标投入").font(.title3.weight(.bold)).foregroundStyle(ZJTheme.ink)
    }
    private var sectionDescription: some View {
        Text("本周各目标的有效计时时长").font(.caption).foregroundStyle(ZJTheme.secondaryInk)
    }
}

private struct GoalTimeRow: View {
    let summary: GoalTimeSummary
    let icon: GoalIcon
    let showsChevron: Bool

    var body: some View {
        HStack(spacing: 12) {
            ZJGoalIcon(iconName: icon.rawValue)
            Text(summary.name)
                .font(.body.weight(.medium))
                .foregroundStyle(ZJTheme.ink)
                .lineLimit(2)
            Spacer(minLength: 8)
            Text(ElapsedTimeText.string(for: summary.seconds))
                .font(.subheadline)
                .foregroundStyle(ZJTheme.secondaryInk)
                .monospacedDigit()
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(ZJTheme.secondaryInk)
                    .accessibilityHidden(true)
            }
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
    }
}
