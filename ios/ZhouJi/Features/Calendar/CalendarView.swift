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
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 12)
                                    .zjCard()
                                daySummary(facts, now: context.date)
                                if viewportHeight >= 700 && !dynamicTypeSize.isAccessibilitySize {
                                    Text("好的时光，都在路上。")
                                        .font(.subheadline)
                                        .foregroundStyle(ZJTheme.secondaryInk)
                                        .padding(.top, 6)
                                }
                            }
                            .padding(.horizontal, ZJTheme.pagePadding)
                            .padding(.top, 20)
                        }
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { viewportHeight = $0 }
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
                    .safeAreaInset(edge: .top, spacing: 0) { dayReviewHeader }
                    .toolbar(.hidden, for: .navigationBar)
                }
                .tint(ZJTheme.accent)
            }
        }
    }

    private func monthGrid(activity: Set<Date>, now: Date) -> some View {
        let cells = CalendarFactsService.monthDays(containing: month)
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7), spacing: 4) {
            ForEach(Array(["日", "一", "二", "三", "四", "五", "六"].enumerated()), id: \.offset) { _, title in
                Text(title)
                    .font(ZJTheme.titleFont(17, relativeTo: .subheadline))
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
                .font(.system(.callout, design: ZJTheme.numberDesign, weight: selected || today ? .semibold : .regular))
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

    private var monthHeader: some View {
        let calendar = Calendar.current
        return HStack(alignment: .center) {
            Button {
                month = .now
                selectedDate = .now
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(String(calendar.component(.year, from: month)))
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(ZJTheme.secondaryInk)
                    Text("\(calendar.component(.month, from: month))月")
                        .font(.largeTitle.weight(.bold))
                        .foregroundStyle(ZJTheme.ink)
                }
                .contentShape(Rectangle())
            }
            .accessibilityLabel("回到今天")
            .accessibilityIdentifier("calendar.today")
            Spacer()
            HStack(spacing: 8) {
                Button { moveMonth(-1) } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(ZJTheme.ink)
                        .frame(width: 44, height: 44)
                        .background(ZJTheme.surface, in: Circle())
                        .compositingGroup()
                        .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 4)
                }
                .accessibilityLabel("上个月")
                .accessibilityIdentifier("calendar.previousMonth")
                Button { moveMonth(1) } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(ZJTheme.onAccent)
                        .frame(width: 44, height: 44)
                        .background(ZJTheme.accent, in: Circle())
                }
                .accessibilityLabel("下个月")
                .accessibilityIdentifier("calendar.nextMonth")
            }
        }
        .buttonStyle(.plain)
    }

    /// The selected date above a "当天回顾" title, with a round close button.
    private var dayReviewHeader: some View {
        let calendar = Calendar.current
        let weekday = selectedDate.formatted(.dateTime.weekday(.wide).locale(Locale(identifier: "zh_CN")))
        let isToday = calendar.isDateInToday(selectedDate)
        return HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(calendar.component(.month, from: selectedDate))月\(calendar.component(.day, from: selectedDate))日 · \(weekday)\(isToday ? " · 今天" : "")")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(ZJTheme.secondaryInk)
                    .accessibilityIdentifier("calendar.selectedDate")
                Text("当天回顾")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(ZJTheme.ink)
                    .accessibilityAddTraits(.isHeader)
            }
            Spacer(minLength: 12)
            Button { isDayPresented = false } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(ZJTheme.ink)
                    .frame(width: 44, height: 44)
                    .background(ZJTheme.surface, in: Circle())
                    .compositingGroup()
                    .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 4)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("关闭")
            .accessibilityIdentifier("calendar.closeDetails")
        }
        .padding(.horizontal, ZJTheme.pagePadding + 2)
        .padding(.top, 18)
        .padding(.bottom, 6)
        .background(ZJTheme.pageBackground)
    }

    private func daySummary(_ facts: CalendarDayFacts, now: Date) -> some View {
        let calendar = Calendar.current
        let isToday = calendar.isDate(selectedDate, inSameDayAs: now)
        let weekday = selectedDate.formatted(.dateTime.weekday(.wide).locale(Locale(identifier: "zh_CN")))
        return Button { isDayPresented = true } label: {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("\(calendar.component(.month, from: selectedDate))月\(calendar.component(.day, from: selectedDate))日")
                        .font(.headline.weight(.bold))
                        .accessibilityIdentifier("calendar.selectedDate")
                    Text(isToday ? "\(weekday) · 今天" : weekday)
                        .font(.subheadline)
                        .foregroundStyle(ZJTheme.secondaryOnEmphasis)
                    Spacer(minLength: 8)
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(ZJTheme.emphasisSurface)
                        .frame(width: 36, height: 36)
                        .background(ZJTheme.onEmphasis, in: Circle())
                        .accessibilityHidden(true)
                }
                HStack(alignment: .bottom, spacing: 12) {
                    summaryMetric(title: "完成", value: "\(facts.completions.count) 件")
                        .accessibilityLabel("\(facts.completions.count) 件完成")
                        .accessibilityIdentifier("calendar.completed")
                    summaryMetric(title: "有效投入", value: ElapsedTimeText.string(for: facts.seconds))
                        .accessibilityLabel("有效投入 \(ElapsedTimeText.string(for: facts.seconds))")
                        .accessibilityIdentifier("calendar.duration")
                }
                if facts.isEmpty {
                    Text("这一天还没有留下记录。从一件小事开始，也很好。")
                        .font(.caption)
                        .foregroundStyle(ZJTheme.secondaryOnEmphasis)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("calendar.empty")
                }
            }
            .foregroundStyle(ZJTheme.onEmphasis)
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(ZJInkBlock())
            .contentShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("calendar.summary")
        .accessibilityHint("查看当天完成事项和实际投入明细")
    }

    private func summaryMetric(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(ZJTheme.secondaryOnEmphasis)
            Text(value)
                .font(.system(.title, design: ZJTheme.numberDesign, weight: .light))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private func dailyJournal(_ facts: CalendarDayFacts, now: Date) -> some View {
        let calendar = Calendar.current
        let isToday = calendar.isDate(selectedDate, inSameDayAs: now)
        let tiles = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: 10))
            : AnyLayout(HStackLayout(spacing: 10))
        return VStack(alignment: .leading, spacing: 14) {
            tiles {
                journalTile(title: "完成", value: "\(facts.completions.count) 件", isInk: true)
                    .accessibilityLabel("\(facts.completions.count) 件完成")
                    .accessibilityIdentifier("calendar.completed")
                journalTile(title: "有效投入", value: ElapsedTimeText.string(for: facts.seconds), isInk: false)
                    .accessibilityLabel("有效投入 \(ElapsedTimeText.string(for: facts.seconds))")
                    .accessibilityIdentifier("calendar.duration")
            }
            if facts.isEmpty {
                Text("这一天还没有留下记录。\n从一件小事开始，也很好。")
                    .font(.subheadline)
                    .foregroundStyle(ZJTheme.secondaryInk)
                    .lineSpacing(5)
                    .padding(.vertical, 10)
                    .accessibilityIdentifier("calendar.empty")
            }
            if !facts.completions.isEmpty {
                Text("完成的事")
                    .font(.headline)
                    .foregroundStyle(ZJTheme.ink)
                    .padding(.top, 8)
                VStack(spacing: 0) {
                    ForEach(facts.completions) { completion in
                        HStack(spacing: 12) {
                            Image(systemName: "checkmark")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(ZJTheme.onAccent)
                                .frame(width: 22, height: 22)
                                .background(ZJTheme.accent, in: Circle())
                                .accessibilityLabel("已完成")
                            Text(completion.title)
                                .font(.body.weight(.semibold))
                                .foregroundStyle(ZJTheme.ink)
                            Spacer(minLength: 8)
                            Text(completion.time.formatted(date: .omitted, time: .shortened))
                                .font(.subheadline)
                                .monospacedDigit()
                                .foregroundStyle(ZJTheme.secondaryInk)
                        }
                        .padding(.horizontal, 16)
                        .frame(minHeight: 54)
                        .accessibilityElement(children: .combine)
                        if completion.id != facts.completions.last?.id {
                            Divider().overlay(ZJTheme.divider).padding(.horizontal, 16)
                        }
                    }
                }
                .zjCard()
            }
            if !facts.timings.isEmpty {
                Text("投入记录")
                    .font(.headline)
                    .foregroundStyle(ZJTheme.ink)
                    .padding(.top, 8)
                ForEach(facts.timings) { timing in
                    let isActive = isToday && timing.state != .finished
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(timing.title)
                                .font(.body.weight(.semibold))
                            Text(timing.goalName ?? "无目标")
                                .font(.caption)
                                .foregroundStyle(isActive ? ZJTheme.secondaryOnEmphasis : ZJTheme.secondaryInk)
                        }
                        Spacer(minLength: 8)
                        if isActive {
                            Text(timing.state == .running ? "计时中" : "已暂停")
                                .font(.caption2.weight(.semibold))
                                .padding(.horizontal, 9)
                                .padding(.vertical, 4)
                                .background(ZJTheme.onEmphasis.opacity(0.14), in: Capsule())
                        }
                        Text(ElapsedTimeText.string(for: timing.seconds))
                            .font(.system(.title3, design: ZJTheme.numberDesign, weight: .light))
                            .monospacedDigit()
                    }
                    .foregroundStyle(isActive ? ZJTheme.onEmphasis : ZJTheme.ink)
                    .padding(.horizontal, 18)
                    .frame(maxWidth: .infinity, minHeight: 66)
                    .background {
                        if isActive {
                            ZJInkBlock(cornerRadius: 22)
                        } else {
                            RoundedRectangle(cornerRadius: 22, style: .continuous)
                                .fill(ZJTheme.surface)
                                .shadow(color: .black.opacity(0.05), radius: 10, x: 0, y: 4)
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
                Text("名称为计时开始时的快照；跨午夜的计时只计入当天部分。")
                    .font(.caption)
                    .foregroundStyle(ZJTheme.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func journalTile(title: String, value: String, isInk: Bool) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.caption)
                .foregroundStyle(isInk ? ZJTheme.secondaryOnEmphasis : ZJTheme.secondaryInk)
            Text(value)
                .font(.system(.title, design: ZJTheme.numberDesign, weight: .light))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .foregroundStyle(isInk ? ZJTheme.onEmphasis : ZJTheme.ink)
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 96, alignment: .leading)
        .background {
            if isInk {
                RoundedRectangle(cornerRadius: 24, style: .continuous).fill(ZJTheme.emphasisSurface)
            } else {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(ZJTheme.surface)
                    .shadow(color: .black.opacity(0.05), radius: 10, x: 0, y: 4)
            }
        }
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
