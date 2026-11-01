import SwiftData
import SwiftUI
import UIKit

struct TodayView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(TimerController.self) private var timer
    @Environment(AccountStore.self) private var account

    @Query(
        filter: #Predicate<TodoTask> { $0.deletedAt == nil },
        sort: \TodoTask.createdAt
    )
    private var visibleTasks: [TodoTask]

    @State private var isTimerPresented = false
    @State private var pendingTimerTask: TodoTask?
    @State private var undoCandidate: TodoTask?
    @State private var undoDismissTask: Task<Void, Never>?
    @State private var presentedError: String?
    @State private var referenceDate = Date.now
    @Binding private var navigationPath: [TodayDestination]
    private let onOpenProfile: () -> Void

    init(navigationPath: Binding<[TodayDestination]>, onOpenProfile: @escaping () -> Void = {}) {
        _navigationPath = navigationPath
        self.onOpenProfile = onOpenProfile
    }

    private var incompleteTasks: [TodoTask] {
        visibleTasks.filter { !$0.isCompleted }
    }

    private var completedTodayTasks: [TodoTask] {
        let today = DateBoundaries.day(containing: referenceDate)
        return visibleTasks
            .filter { task in
                guard let completedAt = task.completedAt else { return false }
                return today.contains(completedAt)
            }
            .sorted { lhs, rhs in
                (lhs.completedAt ?? .distantPast) > (rhs.completedAt ?? .distantPast)
            }
    }

    var body: some View {
        NavigationStack(path: $navigationPath) {
            ScrollViewReader { scroll in
                VStack(spacing: 0) {
                    GeometryReader { proxy in
                        List {
                            let incompleteTasks = self.incompleteTasks
                            let completedTodayTasks = self.completedTodayTasks
                            todayHeaderContent(size: proxy.size, isQuiet: incompleteTasks.isEmpty,
                                               hasCompletedTasks: !completedTodayTasks.isEmpty)
                                .frame(width: proxy.size.width)
                                // Pin the title while the row grows into the resting card.
                                .frame(maxHeight: .infinity, alignment: .top)
                                .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                                .listRowSeparator(.hidden)
                                .listRowBackground(Color.clear)
                                .id("today.header")

                            // One ForEach holds both groups, so a finished task keeps its identity and
                            // slides down into “今日完成” instead of fading out and back in.
                            ForEach(listItems(incomplete: incompleteTasks, completed: completedTodayTasks)) { item in
                                switch item {
                                case let .heading(title, count):
                                    taskSectionHeader(title: title, count: count)
                                case let .task(task, isFirst, isLast):
                                    taskRow(for: task, isFirst: isFirst, isLast: isLast)
                                }
                            }
                        }
                        .listStyle(.plain)
                        .contentMargins(.top, 0, for: .scrollContent)
                        .contentMargins(.bottom, 12, for: .scrollContent)
                        .contentMargins(.horizontal, 0, for: .scrollContent)
                        .scrollContentBackground(.hidden)
                        .background(Color.clear)
                    }
                    .clipped()
                    bottomControls
                }
                .background(ZJTheme.pageBackground.ignoresSafeArea())
                .navigationDestination(for: TodayDestination.self) { destination in
                    switch destination {
                    case .newTask: NewTaskView()
                    }
                }
                .toolbar(.hidden, for: .navigationBar)
                .sheet(isPresented: $isTimerPresented) {
                    TimerSheet()
                }
                .timerSwitchConfirmation(pendingTask: $pendingTimerTask) { task in
                    if timer.switchTo(task) {
                        isTimerPresented = true
                    } else {
                        presentTimerErrorIfNeeded()
                    }
                }
                .alert(
                    "操作未完成",
                    isPresented: Binding(
                        get: { presentedError != nil },
                        set: { if !$0 { presentedError = nil } }
                    )
                ) {
                    Button("好", role: .cancel) {
                        presentedError = nil
                    }
                } message: {
                    Text(presentedError ?? "请稍后重试。")
                }
                .task {
                    presentTimerErrorIfNeeded()
                }
                .onChange(of: scenePhase) { _, newPhase in
                    if newPhase == .active {
                        referenceDate = .now
                        presentTimerErrorIfNeeded()
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in
                    referenceDate = .now
                }
                .onDisappear {
                    undoDismissTask?.cancel()
                }
                .onChange(of: incompleteTasks.isEmpty) { _, isEmpty in
                    guard isEmpty else { return }
                    // Let the finished row land in “今日完成” first, then glide back to the resting card.
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(450))
                        guard self.incompleteTasks.isEmpty else { return }
                        withAnimation(.smooth(duration: 0.35)) {
                            scroll.scrollTo("today.header", anchor: .top)
                        }
                    }
                }
            }
        }
    }

    private func todayHeaderContent(size: CGSize, isQuiet: Bool, hasCompletedTasks: Bool) -> some View {
        let isCompact = size.height < size.width * 1.2 + 192
        let avatar = ProfileAvatar(rawValue: account.account?.avatar ?? "") ?? .standard
        return VStack(spacing: isCompact ? 0 : 20) {
            TodayHeader(date: referenceDate, isQuiet: isQuiet,
                        isDayComplete: isQuiet && hasCompletedTasks,
                        avatar: avatar, onOpenProfile: onOpenProfile)
            if !isQuiet && timer.activeSession != nil {
                activeTimerCard
                    .padding(.horizontal, ZJTheme.pagePadding + 2)
                    .padding(.top, 18)
            }
            if isQuiet {
                firstTaskButton(isCompact: isCompact)
                    .transition(.opacity)
            }
        }
    }

    private func listItems(incomplete: [TodoTask], completed: [TodoTask]) -> [TodayListItem] {
        var items: [TodayListItem] = []
        if !incomplete.isEmpty {
            items.append(.heading("未完成", count: incomplete.count))
            items += incomplete.map { .task($0, isFirst: true, isLast: true) }
        }
        if !completed.isEmpty {
            items.append(.heading("今日完成", count: completed.count))
            items += completed.map { task in
                .task(task, isFirst: task.id == completed.first?.id, isLast: task.id == completed.last?.id)
            }
        }
        return items
    }

    private func taskSectionHeader(title: String, count: Int) -> some View {
        // Every task has its own floating card, so the section title sits on the page.
        ZJSectionHeader(title: title, count: count)
            .listRowInsets(EdgeInsets(top: 34, leading: ZJTheme.pagePadding + 4,
                                     bottom: 8, trailing: ZJTheme.pagePadding + 4))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
    }

    /// Pending and finished tasks share one row so a completed task moves instead of being replaced:
    /// pending rows float as separate white cards, finished ones join a translucent grouped card.
    private func taskRow(for task: TodoTask, isFirst: Bool, isLast: Bool) -> some View {
        let isDone = task.isCompleted
        let radius: (Bool) -> CGFloat = { isDone && !$0 ? 0 : 20 }
        return TaskRow(
            task: task,
            isActivelyTimed: !isDone && timer.activeTaskID == task.id,
            animatesCompletion: true,
            onToggleCompletion: { toggleCompletion(of: task) },
            onStartTimer: { startTimer(for: task) }
        )
        .listRowInsets(EdgeInsets(top: isDone ? 3 : 5, leading: ZJTheme.pagePadding + 12,
                                 bottom: isDone ? 3 : 5, trailing: ZJTheme.pagePadding + (isDone ? 16 : 12)))
        .listRowSeparatorTint(ZJTheme.divider)
        .listRowSeparator(.hidden, edges: .top)
        .listRowSeparator(isDone && !isLast ? .visible : .hidden, edges: .bottom)
        .alignmentGuide(.listRowSeparatorLeading) { _ in 8 }
        .alignmentGuide(.listRowSeparatorTrailing) { dimensions in dimensions.width }
        .listRowBackground(
            UnevenRoundedRectangle(topLeadingRadius: radius(isFirst), bottomLeadingRadius: radius(isLast),
                                   bottomTrailingRadius: radius(isLast), topTrailingRadius: radius(isFirst),
                                   style: .continuous)
                .fill(isDone ? ZJTheme.surface.opacity(0.6) : ZJTheme.surface)
                .shadow(color: .black.opacity(isDone ? 0 : 0.05), radius: 10, x: 0, y: 4)
                .padding(.horizontal, ZJTheme.pagePadding)
                .padding(.vertical, isDone ? 0 : 5)
                .allowsHitTesting(false)
        )
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                delete(task)
            } label: {
                Label("删除", systemImage: "trash")
            }
        }
    }

    @ViewBuilder
    private var bottomControls: some View {
        if let undoCandidate {
            TaskUndoToast(
                taskTitle: undoCandidate.title,
                onUndo: { undoDelete(undoCandidate) }
            )
            .id(undoCandidate.id)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .padding(.top, 4)
            .padding(.bottom, 12)
        }
    }

    private func firstTaskButton(isCompact: Bool) -> some View {
        // A white button that floats under the black resting card.
        let diameter: CGFloat = isCompact ? 60 : 72
        return Button {
            navigationPath.append(.newTask)
        } label: {
            VStack(spacing: isCompact ? 4 : 14) {
                Image(systemName: "plus")
                    .font(.system(size: diameter * 46 / 124, weight: .regular, design: .rounded))
                    .foregroundStyle(ZJTheme.ink)
                    .frame(width: diameter, height: diameter)
                    .background(ZJTheme.surface, in: Circle())
                    .compositingGroup()
                    .shadow(color: .black.opacity(0.10), radius: 14, x: 0, y: 8)
                Text("记一件事")
                    .font(ZJTheme.titleFont(24, relativeTo: .title3))
                    .foregroundStyle(ZJTheme.ink)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("添加任务")
        .accessibilityIdentifier("today.firstTask")
    }

    /// The running timer sits at the top of Today as a black card; tapping it opens the timer page.
    private var activeTimerCard: some View {
        HStack(alignment: .bottom, spacing: 12) {
            Button {
                isTimerPresented = true
            } label: {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 8) {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(ZJTheme.onEmphasis)
                                .frame(width: 6, height: 6)
                                .opacity(timer.isRunning ? 1 : 0.4)
                            Text(timer.isRunning ? "计时中" : "已暂停")
                                .font(.caption.weight(.semibold))
                        }
                        .padding(.horizontal, 10)
                        .frame(minHeight: 26)
                        .background(ZJTheme.onEmphasis.opacity(0.12), in: Capsule())
                        if let goal = timer.activeSession?.goalNameSnapshot {
                            Text(goal)
                                .font(.caption)
                                .foregroundStyle(ZJTheme.secondaryOnEmphasis)
                                .lineLimit(1)
                        }
                    }
                    Spacer(minLength: 18)
                    Text(timer.activeSession?.taskTitleSnapshot ?? "本次计时")
                        .font(.headline.weight(.semibold))
                        .lineLimit(1)
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        Text(TimerMath.formattedDuration(timer.elapsed(at: context.date)))
                            .font(.system(size: 38, weight: .light, design: ZJTheme.numberDesign))
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                    }
                    .padding(.top, 4)
                }
                .foregroundStyle(ZJTheme.onEmphasis)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("查看当前计时")

            Button {
                if timer.isRunning { _ = timer.pause() } else { _ = timer.resume() }
                presentTimerErrorIfNeeded()
            } label: {
                Image(systemName: timer.isRunning ? "pause.fill" : "play.fill")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(ZJTheme.emphasisSurface)
                    .frame(width: 48, height: 48)
                    .background(ZJTheme.onEmphasis, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(timer.isRunning ? "暂停计时" : "继续计时")
        }
        .padding(.leading, 22)
        .padding(.trailing, 20)
        .padding(.vertical, 20)
        .frame(minHeight: 168)
        .background(ZJInkBlock())
    }

    private func toggleCompletion(of task: TodoTask) {
        do {
            try TaskService.setCompleted(task, completed: !task.isCompleted, timer: timer, in: modelContext)
        } catch {
            presentedError = error.localizedDescription
        }
    }

    private func startTimer(for task: TodoTask) {
        switch timer.requestStart(for: task) {
        case .started, .showCurrent:
            isTimerPresented = true
        case .confirmSwitch:
            pendingTimerTask = task
        case .failed:
            break
        }
        presentTimerErrorIfNeeded()
    }

    private func delete(_ task: TodoTask) {
        do {
            try TaskService.softDelete(task, timer: timer, in: modelContext)
            undoCandidate = task
            scheduleUndoDismissal()
        } catch {
            presentedError = error.localizedDescription
        }
    }

    private func undoDelete(_ task: TodoTask) {
        undoDismissTask?.cancel()
        do {
            try TaskService.restore(task, in: modelContext)
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) {
                undoCandidate = nil
            }
        } catch {
            presentedError = error.localizedDescription
        }
    }

    private func scheduleUndoDismissal() {
        undoDismissTask?.cancel()
        undoDismissTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) {
                undoCandidate = nil
            }
        }
    }

    private func presentTimerErrorIfNeeded() {
        guard let message = timer.errorMessage else { return }
        presentedError = message
        timer.clearError()
    }
}

enum TodayDestination: Hashable {
    case newTask
}

/// A date title with the avatar; with nothing left to do, a black card carries the message.
private struct TodayHeader: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let date: Date
    let isQuiet: Bool
    let isDayComplete: Bool
    let avatar: ProfileAvatar
    let onOpenProfile: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .center) {
                titleBlock
                Spacer(minLength: 12)
                Button(action: onOpenProfile) {
                    ProfileAvatarView(avatar: avatar, size: 44)
                        .overlay { Circle().stroke(ZJTheme.surface, lineWidth: 2) }
                        .compositingGroup()
                        .shadow(color: .black.opacity(0.10), radius: 8, x: 0, y: 4)
                        .frame(width: 48, height: 48)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("我的")
                .accessibilityIdentifier("today.profile")
            }
            if isQuiet {
                restingCard
            }
        }
        .padding(.horizontal, ZJTheme.pagePadding + 2)
        .padding(.top, 24)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(date.formatted(.dateTime.month(.defaultDigits).day().weekday(.wide).locale(Locale(identifier: "zh_CN"))))
                .font(.subheadline.weight(.medium))
                .foregroundStyle(ZJTheme.secondaryInk)
            Text("今天")
                .font(.largeTitle.weight(.bold))
                .foregroundStyle(ZJTheme.ink)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("today.greeting")
        }
    }

    private var restingCard: some View {
        Text(isDayComplete ? "今天的事都完成了，\n给自己一点休息的时间。" : "新的一天，\n从一件小事开始。")
            .contentTransition(.opacity)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.28), value: isDayComplete)
            .font(.title3.weight(.semibold))
            .lineSpacing(5)
            .foregroundStyle(ZJTheme.onEmphasis)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, minHeight: 55, alignment: .bottomLeading)
            .padding(22)
            .background(ZJInkBlock())
            .accessibilityIdentifier("today.message")
    }
}

#Preview {
    TodayView(navigationPath: .constant([]))
        .environment(TimerController())
        .modelContainer(for: [Goal.self, TodoTask.self, TimingSession.self], inMemory: true)
}

/// A task keeps the same id whether it is pending or finished, so List animates it as a move.
private enum TodayListItem: Identifiable {
    case heading(String, count: Int)
    case task(TodoTask, isFirst: Bool, isLast: Bool)

    var id: String {
        switch self {
        case let .heading(title, _): "heading.\(title)"
        case let .task(task, _, _): task.id.uuidString
        }
    }
}
