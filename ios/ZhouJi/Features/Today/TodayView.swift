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
        NavigationStack {
            ZStack {
                ZJTheme.pageBackground.ignoresSafeArea()

                List {
                    TodayHeader(date: referenceDate)
                        .listRowInsets(EdgeInsets(top: 12, leading: 4, bottom: 12, trailing: 4))
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)

                    if incompleteTasks.isEmpty {
                        ZJEmptyState(
                            title: completedTodayTasks.isEmpty ? "今天想做点什么？" : "今天的事都完成了",
                            message: completedTodayTasks.isEmpty ? "记下一件小事，然后开始。" : "辛苦了，新的任务随时可以再记。",
                            systemImage: completedTodayTasks.isEmpty ? "pencil.line" : "checkmark"
                        )
                            .padding(18)
                            .zjCard()
                            .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                    } else {
                        Section {
                            ZJSectionHeader(title: "未完成", count: incompleteTasks.count)
                                .listRowInsets(EdgeInsets(top: 18, leading: 18, bottom: 8, trailing: 18))
                                .listRowSeparator(.hidden)

                            ForEach(incompleteTasks) { task in
                                row(for: task)
                            }
                        }
                    }

                    if !completedTodayTasks.isEmpty {
                        Section {
                            ZJSectionHeader(title: "已完成", count: completedTodayTasks.count)
                                .listRowInsets(EdgeInsets(top: 18, leading: 18, bottom: 8, trailing: 18))
                                .listRowSeparator(.hidden)

                            ForEach(completedTodayTasks) { task in
                                row(for: task)
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .listSectionSpacing(16)
                .scrollContentBackground(.hidden)
                .background(Color.clear)
            }
            .toolbar(.hidden, for: .navigationBar)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                bottomControls
            }
            .sheet(isPresented: $isTimerPresented) {
                TimerSheet()
            }
            .confirmationDialog(
                "切换计时任务？",
                isPresented: Binding(
                    get: { pendingTimerTask != nil },
                    set: { if !$0 { pendingTimerTask = nil } }
                ),
                titleVisibility: .visible
            ) {
                if let pendingTimerTask, let currentTitle = timer.activeSession?.taskTitleSnapshot {
                    Button("结束“\(currentTitle)”并开始新计时") {
                        if timer.switchTo(pendingTimerTask) {
                            isTimerPresented = true
                        } else {
                            presentTimerErrorIfNeeded()
                        }
                        self.pendingTimerTask = nil
                    }
                }
                Button("取消", role: .cancel) {
                    pendingTimerTask = nil
                }
            } message: {
                if let pendingTimerTask {
                    Text("确认后将保存当前计时，并开始“\(pendingTimerTask.title)”。")
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
        }
    }

    private func row(for task: TodoTask) -> some View {
        TaskRow(
            task: task,
            isActivelyTimed: timer.activeTaskID == task.id,
            onToggleCompletion: { toggleCompletion(of: task) },
            onStartTimer: { startTimer(for: task) }
        )
        .listRowInsets(EdgeInsets(top: 0, leading: 12, bottom: 0, trailing: 12))
        .listRowSeparatorTint(ZJTheme.divider)
        .listRowBackground(ZJTheme.surface)
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

            NavigationLink {
                NewTaskView()
            } label: {
                Label {
                    Text("添加任务")
                        .foregroundStyle(ZJTheme.secondaryInk)
                } icon: {
                    Image(systemName: "plus")
                        .foregroundStyle(ZJTheme.accent)
                }
                .font(.headline)
                .padding(.horizontal, 22)
                .frame(minHeight: ZJTheme.controlHeight)
            }
            .buttonStyle(.zjSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, ZJTheme.pagePadding)
        }
        .padding(.top, 8)
        .padding(.bottom, 8)
        .background(ZJTheme.background.opacity(0.96))
    }

    private var activeTimerBar: some View {
        Button {
            isTimerPresented = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: timer.isRunning ? "waveform" : "pause.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(ZJTheme.timerAccent)
                    .frame(width: 32, height: 32)

                VStack(alignment: .leading, spacing: 2) {
                    Text(timer.activeSession?.taskTitleSnapshot ?? "本次计时")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(ZJTheme.ink)
                        .lineLimit(1)

                    Text(timer.isRunning ? "正在投入" : "已经暂停")
                        .font(.caption)
                        .foregroundStyle(ZJTheme.secondaryInk)
                }

                Spacer()

                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text(TimerMath.formattedDuration(timer.elapsed(at: context.date)))
                        .font(.system(.subheadline, design: .rounded, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(ZJTheme.ink)
                }

                Image(systemName: "chevron.up")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(ZJTheme.secondaryInk)
            }
            .padding(.horizontal, ZJTheme.pagePadding)
            .padding(.vertical, 10)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("查看当前计时")
        .zjCard()
        .padding(.horizontal, ZJTheme.pagePadding)
    }

    private func toggleCompletion(of task: TodoTask) {
        if !task.isCompleted, timer.activeTaskID == task.id {
            guard timer.finishActiveSession() else {
                presentTimerErrorIfNeeded()
                return
            }
        }

        do {
            try TaskService.setCompleted(task, completed: !task.isCompleted, in: modelContext)
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
        if timer.activeTaskID == task.id {
            guard timer.finishActiveSession() else {
                presentTimerErrorIfNeeded()
                return
            }
        }

        do {
            try TaskService.softDelete(task, in: modelContext)
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

private struct TodayHeader: View {
    let date: Date

    @MainActor
    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日 EEE"
        return formatter
    }()

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .bottom, spacing: 18) {
                headerCopy
                Spacer(minLength: 8)
                TodaySkyWindow()
            }

            headerCopy
        }
    }

    private var headerCopy: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("粥记")
                .font(.title2.weight(.bold))
                .foregroundStyle(ZJTheme.ink)

            HStack(alignment: .firstTextBaseline, spacing: 7) {
                Text("你好，今天")
                    .font(.title.weight(.bold))
                    .foregroundStyle(ZJTheme.ink)

                Image(systemName: "sparkles")
                    .font(.title3.weight(.medium))
                    .foregroundStyle(ZJTheme.timerAccent)
                    .accessibilityHidden(true)
            }

            Text("专注当下，一件件完成吧。")
                .font(.subheadline)
                .foregroundStyle(ZJTheme.secondaryInk)

            Text(Self.dateFormatter.string(from: date))
                .font(.subheadline.weight(.medium))
                .foregroundStyle(ZJTheme.secondaryInk)
                .padding(.top, 18)
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

private struct TodaySkyWindow: View {
    var body: some View {
        let shape = UnevenRoundedRectangle(
            topLeadingRadius: 56,
            bottomLeadingRadius: 14,
            bottomTrailingRadius: 14,
            topTrailingRadius: 56,
            style: .continuous
        )

        if let illustration = UIImage(named: "TodayJourney") {
            Image(uiImage: illustration)
                .resizable()
                .scaledToFill()
                .frame(width: 116, height: 156)
                .scaleEffect(1.08)
                .compositingGroup()
                .clipShape(shape)
                .overlay {
                    shape.stroke(ZJTheme.surface.opacity(0.9), lineWidth: 2)
                }
                .frame(width: 116, height: 156)
                .shadow(color: ZJTheme.accent.opacity(0.12), radius: 18, x: 0, y: 8)
                .accessibilityHidden(true)
        }
    }
}

#Preview {
    TodayView()
        .environment(TimerController())
        .modelContainer(for: [Goal.self, TodoTask.self, TimingSession.self], inMemory: true)
}
