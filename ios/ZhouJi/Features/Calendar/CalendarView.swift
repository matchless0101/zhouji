import SwiftData
import SwiftUI

struct CalendarView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Query private var tasks: [TodoTask]
    @Query private var sessions: [TimingSession]
    @State private var month = Date.now
    @State private var selectedDate = Date.now
    @State private var isDayPresented = false
    @State private var viewportHeight: CGFloat = 0

    var body: some View {
        NavigationStack {
            Group {
                switch Result(catching: { try CalendarFactsService.projection(selectedDate, month: month, tasks: tasks, sessions: sessions) }) {
                case .failure(let error):
                    Text(error.localizedDescription).foregroundStyle(ZJTheme.secondaryInk).padding()
                case .success(let projection):
                    TimelineView(.periodic(from: .now, by: projection.isRunning ? 1 : 60)) { context in
                        let facts = projection.day(now: context.date)
                        let activity = projection.activityDays(now: context.date)
                        ScrollView {
                            VStack(spacing: 14) {
                                monthHeader
                                monthGrid(activity: activity, now: context.date)
                                    .background(ZJTheme.pageBackground)
                                daySummary(facts)
                                Color.clear
                                    .aspectRatio(1.2, contentMode: .fit)
                                    .padding(.horizontal, -ZJTheme.pagePadding)
                                    .accessibilityHidden(true)
                                    .overlay(alignment: .topTrailing) {
                                        if viewportHeight >= 700 && !dynamicTypeSize.isAccessibilitySize {
                                            Text("好的时光，\n都在路上。")
                                            .font(ZJTheme.handwriting(20, relativeTo: .body))
                                            .lineSpacing(5)
                                            .foregroundStyle(ZJTheme.ink)
                                            .rotationEffect(.degrees(-9))
                                            .padding(.trailing, 28)
                                            .padding(.top, 4)
                                        }
                                    }
                            }
                            .padding(.horizontal, ZJTheme.pagePadding)
                            .padding(.top, 20)
                        }
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { viewportHeight = $0 }
                        .background(alignment: .bottom) {
                            Image(decorative: "LiuliCalendarReference")
                                .resizable()
                                .scaledToFit()
                                .frame(maxWidth: .infinity)
                                .accessibilityHidden(true)
                                .allowsHitTesting(false)
                        }
                    }
                }
            }
            .background(ZJTheme.pageBackground.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $isDayPresented) {
                NavigationStack {
                    Group {
                        switch Result(catching: { try CalendarFactsService.projection(selectedDate, month: month, tasks: tasks, sessions: sessions) }) {
                        case .failure(let error):
                            Text(error.localizedDescription).foregroundStyle(ZJTheme.secondaryInk).padding()
                        case .success(let projection):
                            TimelineView(.periodic(from: .now, by: projection.isRunning ? 1 : 60)) { context in
                                ScrollView {
                                    dailyJournal(projection.day(now: context.date), now: context.date)
                                        .padding(ZJTheme.pagePadding)
                                }
                            }
                        }
                    }
                    .background(ZJTheme.pageBackground.ignoresSafeArea())
                    .navigationTitle("当天回顾")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("关闭") { isDayPresented = false }
                                .accessibilityIdentifier("calendar.closeDetails")
                        }
                    }
                }
                .tint(ZJTheme.accent)
            }
        }
    }

    private var monthHeader: some View {
        HStack {
            Button { moveMonth(-1) } label: {
                Image(systemName: "chevron.left").frame(width: 44, height: 44)
            }
            .accessibilityLabel("上个月")
            .accessibilityIdentifier("calendar.previousMonth")
            Spacer()
            Button {
                month = .now
                selectedDate = .now
            } label: {
                Text(String(format: "%d.%02d", Calendar.current.component(.year, from: month), Calendar.current.component(.month, from: month)))
                    .font(ZJTheme.handwriting(28, relativeTo: .title2))
                    .padding(.vertical, 10)
            }
            .accessibilityLabel("回到今天")
            .accessibilityIdentifier("calendar.today")
            Spacer()
            Button { moveMonth(1) } label: {
                Image(systemName: "chevron.right").frame(width: 44, height: 44)
            }
            .accessibilityLabel("下个月")
            .accessibilityIdentifier("calendar.nextMonth")
        }
        .foregroundStyle(ZJTheme.ink)
        .buttonStyle(.plain)
    }

    private func monthGrid(activity: Set<Date>, now: Date) -> some View {
        let cells = CalendarFactsService.monthDays(containing: month)
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7), spacing: 4) {
            ForEach(Array(["日", "一", "二", "三", "四", "五", "六"].enumerated()), id: \.offset) { _, title in
                Text(title)
                    .font(ZJTheme.handwriting(17, relativeTo: .subheadline))
                    .foregroundStyle(ZJTheme.secondaryInk)
                    .frame(height: 32)
                    .accessibilityHidden(true)
            }
            ForEach(cells.indices, id: \.self) { index in
                if let date = cells[index] {
                    dayButton(date, hasActivity: activity.contains(date), now: now)
                } else {
                    Color.clear.frame(height: 44).accessibilityHidden(true)
                }
            }
        }
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .accessibilityLabel("月历")
    }

    private func dayButton(_ date: Date, hasActivity: Bool, now: Date) -> some View {
        let selected = Calendar.current.isDate(date, inSameDayAs: selectedDate)
        let today = Calendar.current.isDate(date, inSameDayAs: now)
        let dayNumber = Calendar.current.component(.day, from: date)
        return Button { selectedDate = date } label: {
            Text("\(dayNumber)")
                .font(.system(.callout, design: .rounded, weight: selected || today ? .semibold : .regular))
                .foregroundStyle(selected ? ZJTheme.onAccent : ZJTheme.ink)
                .frame(width: 36, height: 36)
                .background(selected ? ZJTheme.accent : .clear, in: Circle())
                .overlay { if today && !selected { Circle().stroke(ZJTheme.accent, lineWidth: 1) } }
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .overlay(alignment: .bottom) {
                    if hasActivity {
                        Circle().fill(ZJTheme.success).frame(width: 4, height: 4).padding(.bottom, 1)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(date.formatted(.dateTime.year().month().day().weekday().locale(Locale(identifier: "zh_CN"))))
        .accessibilityValue([today ? "今天" : nil, hasActivity ? "有记录" : "无记录"].compactMap { $0 }.joined(separator: "，"))
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("calendar.day.\(dayNumber)")
    }

    private func daySummary(_ facts: CalendarDayFacts) -> some View {
        Button { isDayPresented = true } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("\(Calendar.current.component(.month, from: selectedDate))月\(Calendar.current.component(.day, from: selectedDate))日")
                        .font(ZJTheme.handwriting(20, relativeTo: .headline))
                        .foregroundStyle(ZJTheme.ink)
                        .accessibilityIdentifier("calendar.selectedDate")
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 16) { summaryMetrics(facts) }
                        VStack(alignment: .leading, spacing: 4) { summaryMetrics(facts) }
                    }
                    if facts.isEmpty {
                        Text("从一件小事开始，也很好。")
                            .font(.caption)
                            .foregroundStyle(ZJTheme.secondaryInk)
                            .accessibilityIdentifier("calendar.empty")
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(ZJTheme.secondaryInk)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .zjCard()
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("calendar.summary")
        .accessibilityHint("查看当天完成事项和实际投入明细")
    }

    @ViewBuilder
    private func summaryMetrics(_ facts: CalendarDayFacts) -> some View {
        Text("\(facts.completions.count) 件完成")
            .accessibilityIdentifier("calendar.completed")
            .font(.subheadline)
            .foregroundStyle(ZJTheme.secondaryInk)
        Label {
            Text(ElapsedTimeText.string(for: facts.seconds))
        } icon: {
            ZJIcon(systemName: "clock", size: 24)
        }
            .accessibilityIdentifier("calendar.duration")
            .font(.subheadline)
            .foregroundStyle(ZJTheme.secondaryInk)
    }

    private func dailyJournal(_ facts: CalendarDayFacts, now: Date) -> some View {
        let metricsLayout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(spacing: 16))
        return VStack(alignment: .leading, spacing: 14) {
            Text("\(Calendar.current.component(.month, from: selectedDate))月\(Calendar.current.component(.day, from: selectedDate))日的记录")
                .font(.headline)
                .foregroundStyle(ZJTheme.ink)
                .accessibilityIdentifier("calendar.selectedDate")
            metricsLayout {
                Text("\(facts.completions.count) 件完成")
                    .accessibilityIdentifier("calendar.completed")
                Label {
                    Text(ElapsedTimeText.string(for: facts.seconds))
                } icon: {
                    ZJIcon(systemName: "clock", size: 24)
                }
                    .accessibilityIdentifier("calendar.duration")
            }
            .font(.subheadline)
            .foregroundStyle(ZJTheme.secondaryInk)
            .frame(maxWidth: .infinity, alignment: .leading)

            if facts.isEmpty {
                Text("这一天还没有留下记录。\n从一件小事开始，也很好。")
                    .font(.subheadline)
                    .foregroundStyle(ZJTheme.secondaryInk)
                    .lineSpacing(5)
                    .padding(.vertical, 10)
                    .accessibilityIdentifier("calendar.empty")
            }
            if !facts.completions.isEmpty {
                ForEach(facts.completions) { completion in
                    journalRow(title: completion.title, detail: completion.time.formatted(date: .omitted, time: .shortened),
                               symbol: ZJTheme.goalSymbol(for: completion.iconName), completed: true)
                }
            }
            if !facts.timings.isEmpty {
                Text("实际投入").font(.caption).foregroundStyle(ZJTheme.secondaryInk)
                ForEach(facts.timings) { timing in
                    let isToday = Calendar.current.isDate(selectedDate, inSameDayAs: now)
                    let status = isToday && timing.state != .finished ? (timing.state == .running ? " · 计时中" : " · 已暂停") : ""
                    journalRow(title: timing.title,
                               detail: [timing.goalName, ElapsedTimeText.string(for: timing.seconds) + status].compactMap { $0 }.joined(separator: " · "),
                               symbol: "clock", completed: false)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .zjCard()
    }

    private func journalRow(title: String, detail: String, symbol: String, completed: Bool) -> some View {
        HStack(spacing: 12) {
            ZJIcon(systemName: symbol, size: 38).frame(width: 28)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.body.weight(.medium)).foregroundStyle(ZJTheme.ink)
                Text(detail).font(.caption).foregroundStyle(ZJTheme.secondaryInk)
            }
            Spacer(minLength: 0)
            if completed {
                Image(systemName: "checkmark.circle.fill").font(.title2).foregroundStyle(ZJTheme.success)
                    .accessibilityLabel("已完成")
            }
        }
        .padding(.vertical, 3)
        .accessibilityElement(children: .combine)
    }

    private func moveMonth(_ offset: Int) {
        let calendar = Calendar.current
        guard let start = calendar.dateInterval(of: .month, for: month)?.start,
              let next = calendar.date(byAdding: .month, value: offset, to: start),
              let days = calendar.range(of: .day, in: .month, for: next) else { return }
        let day = min(calendar.component(.day, from: selectedDate), days.count)
        month = next
        selectedDate = calendar.date(byAdding: .day, value: day - 1, to: next) ?? next
    }
}
