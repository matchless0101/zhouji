import SwiftData
import SwiftUI
import UIKit

struct TodayView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(TimerController.self) private var timer

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

    init(navigationPath: Binding<[TodayDestination]>) {
        _navigationPath = navigationPath
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
                                .frame(minHeight: incompleteTasks.isEmpty ? proxy.size.height : nil, alignment: .top)
                                .animation(nil, value: incompleteTasks.isEmpty)
                                .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                                .listRowSeparator(.hidden)
                                .listRowBackground(Color.clear)
                                .id("today.header")

                            if !incompleteTasks.isEmpty {
                                Section {
                                    taskSectionHeader(title: "未完成", count: incompleteTasks.count)

                                    ForEach(incompleteTasks) { task in
                                        row(for: task)
                                            .id(task.id)
                                    }
                                }
                            }

                            completedTasksSection(tasks: completedTodayTasks)
                        }
                        .listStyle(.plain)
                        .listSectionSpacing(16)
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
                    DispatchQueue.main.async {
                        guard self.incompleteTasks.isEmpty else { return }
                        scroll.scrollTo("today.header", anchor: .top)
                    }
                }
            }
        }
    }

    private func todayHeaderContent(size: CGSize, isQuiet: Bool, hasCompletedTasks: Bool) -> some View {
        let isCompact = size.height < size.width * 1.2 + 192
        return VStack(spacing: isCompact ? 0 : 20) {
            TodayHeader(date: referenceDate, isQuiet: isQuiet,
                        isDayComplete: isQuiet && hasCompletedTasks)
            if isQuiet {
                firstTaskButton(isCompact: isCompact)
                    .transition(.opacity)
            }
        }
    }

    @ViewBuilder
    private func completedTasksSection(tasks: [TodoTask]) -> some View {
        if !tasks.isEmpty {
            Section {
                taskSectionHeader(title: "已完成", count: tasks.count)

                ForEach(tasks) { task in
                    row(for: task)
                }
            }
        }
    }

    private func taskSectionHeader(title: String, count: Int) -> some View {
        // Every task has its own floating card, so the section title sits on the page.
        ZJSectionHeader(title: title, count: count)
            .listRowInsets(EdgeInsets(top: 18, leading: ZJTheme.pagePadding + 4,
                                     bottom: 8, trailing: ZJTheme.pagePadding + 4))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
    }

    private var taskCardBackground: some View {
        RoundedRectangle(cornerRadius: 20, style: .continuous)
            .fill(ZJTheme.surface)
            .shadow(color: .black.opacity(0.05), radius: 10, x: 0, y: 4)
            .padding(.horizontal, ZJTheme.pagePadding)
            .padding(.vertical, 5)
            .allowsHitTesting(false)
    }

    private func row(for task: TodoTask) -> some View {
        TaskRow(
            task: task,
            isActivelyTimed: timer.activeTaskID == task.id,
            animatesCompletion: true,
            onToggleCompletion: { toggleCompletion(of: task) },
            onStartTimer: { startTimer(for: task) }
        )
        .listRowInsets(EdgeInsets(top: 5, leading: ZJTheme.pagePadding + 12,
                                 bottom: 5, trailing: ZJTheme.pagePadding + 12))
        .listRowSeparator(.hidden)
        .listRowBackground(taskCardBackground)
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
        if undoCandidate != nil || timer.activeSession != nil {
            VStack(spacing: 10) {
                if let undoCandidate {
                    TaskUndoToast(
                        taskTitle: undoCandidate.title,
                        onUndo: { undoDelete(undoCandidate) }
                    )
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                if timer.activeSession != nil {
                    activeTimerBar
                }
            }
            .padding(.top, 8)
            .padding(.bottom, 16)
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

    private var activeTimerBar: some View {
        Button {
            isTimerPresented = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: timer.isRunning ? "waveform" : "pause.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(ZJTheme.onEmphasis)
                    .frame(width: 32, height: 32)

                VStack(alignment: .leading, spacing: 2) {
                    Text(timer.activeSession?.taskTitleSnapshot ?? "本次计时")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(ZJTheme.onEmphasis)
                        .lineLimit(1)

                    Text(timer.isRunning ? "正在投入" : "已经暂停")
                        .font(.caption)
                        .foregroundStyle(ZJTheme.secondaryOnEmphasis)
                }

                Spacer()

                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text(TimerMath.formattedDuration(timer.elapsed(at: context.date)))
                        .font(.system(.subheadline, design: ZJTheme.numberDesign, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(ZJTheme.onEmphasis)
                }

                Image(systemName: "chevron.up")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(ZJTheme.secondaryOnEmphasis)
            }
            .padding(.horizontal, ZJTheme.pagePadding)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("查看当前计时")
        .zjEmphasisCard()
        .padding(.horizontal, ZJTheme.pagePadding)
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

/// A date title; with nothing left to do, a black card carries the message.
private struct TodayHeader: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let date: Date
    let isQuiet: Bool
    let isDayComplete: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
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
            if isQuiet {
                Text(isDayComplete ? "今天的事都完成了，\n给自己一点休息的时间。" : "新的一天，\n从一件小事开始。")
                    .contentTransition(.opacity)
                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.28), value: isDayComplete)
                    .font(.title3.weight(.semibold))
                    .lineSpacing(5)
                    .foregroundStyle(ZJTheme.onEmphasis)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, minHeight: 150, alignment: .bottomLeading)
                    .padding(22)
                    .background(ZJInkBlock())
                    .accessibilityIdentifier("today.message")
            }
        }
        .padding(.horizontal, ZJTheme.pagePadding + 2)
        .padding(.top, 24)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#Preview {
    TodayView(navigationPath: .constant([]))
        .environment(TimerController())
        .modelContainer(for: [Goal.self, TodoTask.self, TimingSession.self], inMemory: true)
}
