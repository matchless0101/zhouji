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
    @State private var bottomControlsHeight: CGFloat = 80
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
            ZStack {
                ZJTheme.pageBackground.ignoresSafeArea()

                if incompleteTasks.isEmpty {
                    GeometryReader { proxy in
                        if completedTodayTasks.isEmpty {
                            ScrollView {
                                quietTodayContent(size: proxy.size)
                                    .padding(.bottom, bottomControlsHeight + 12)
                            }
                        } else {
                            List {
                                quietTodayContent(size: proxy.size)
                                    .frame(width: proxy.size.width)
                                    .frame(minHeight: proxy.size.height, alignment: .top)
                                    .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                                    .listRowSeparator(.hidden)
                                    .listRowBackground(Color.clear)
                                completedTasksSection
                            }
                            .listStyle(.plain)
                            .listSectionSpacing(16)
                            .contentMargins(.top, 0, for: .scrollContent)
                            .contentMargins(.bottom, bottomControlsHeight + 12, for: .scrollContent)
                            .contentMargins(.horizontal, 0, for: .scrollContent)
                            .scrollContentBackground(.hidden)
                            .background(Color.clear)
                        }
                    }
                } else {
                    List {
                        TodayHeader(date: referenceDate, isEmpty: false)
                            .padding(.horizontal, -ZJTheme.pagePadding)
                            .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)

                        Section {
                            ZJSectionHeader(title: "未完成", count: incompleteTasks.count)
                                .listRowInsets(EdgeInsets(top: 18, leading: 18, bottom: 8, trailing: 18))
                                .listRowBackground(ZJTheme.surface)
                                .listRowSeparator(.hidden)

                            ForEach(incompleteTasks) { task in
                                row(for: task)
                            }
                        }

                        completedTasksSection
                    }
                    .listStyle(.insetGrouped)
                    .listSectionSpacing(16)
                    .contentMargins(.top, 0, for: .scrollContent)
                    .contentMargins(.bottom, bottomControlsHeight + 12, for: .scrollContent)
                    .contentMargins(.horizontal, ZJTheme.pagePadding, for: .scrollContent)
                    .scrollContentBackground(.hidden)
                    .background(Color.clear)
                }
            }
            .navigationDestination(for: TodayDestination.self) { destination in
                switch destination {
                case .newTask: NewTaskView()
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .overlay(alignment: .bottom) {
                bottomControls
                    .onGeometryChange(for: CGFloat.self) { proxy in
                        proxy.size.height
                    } action: { height in
                        bottomControlsHeight = height
                    }
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

    private func quietTodayContent(size: CGSize) -> some View {
        VStack(spacing: 20) {
            TodayHeader(
                date: referenceDate,
                isEmpty: true,
                isDayComplete: !completedTodayTasks.isEmpty,
                heroHeight: min(size.width * 1.2, max(270, size.height - 212))
            )
            firstTaskButton
        }
    }

    @ViewBuilder
    private var completedTasksSection: some View {
        if !completedTodayTasks.isEmpty {
            Section {
                ZJSectionHeader(title: "已完成", count: completedTodayTasks.count)
                    .listRowInsets(EdgeInsets(top: 12, leading: 18, bottom: 6, trailing: 18))
                    .listRowBackground(ZJTheme.surface)
                    .listRowSeparator(.hidden)

                ForEach(completedTodayTasks) { task in
                    row(for: task)
                }
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
        .alignmentGuide(.listRowSeparatorLeading) { _ in 8 }
        .alignmentGuide(.listRowSeparatorTrailing) { dimensions in dimensions.width - 8 }
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

            if !incompleteTasks.isEmpty {
                NavigationLink(value: TodayDestination.newTask) {
                    Image(systemName: "plus")
                }
                .buttonStyle(ZJAddButtonStyle())
                .accessibilityLabel("添加任务")
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.horizontal, ZJTheme.pagePadding)
            }
        }
        .padding(.top, 8)
        .padding(.bottom, 16)
    }

    private var firstTaskButton: some View {
        Button {
            navigationPath.append(.newTask)
        } label: {
            VStack(spacing: 14) {
                Image(systemName: "plus")
                    .font(.system(size: 46, weight: .regular, design: .rounded))
                    .foregroundStyle(ZJTheme.onAccent)
                    .frame(width: 124, height: 124)
                    .background {
                        Circle().fill(ZJTheme.accent)
                            .overlay {
                                Canvas { context, size in
                                    for index in 0..<420 {
                                        let x = CGFloat((index * 73 + 19) % 997) / 997 * size.width
                                        let y = CGFloat((index * 137 + 47) % 991) / 991 * size.height
                                        let side: CGFloat = index.isMultiple(of: 5) ? 1.1 : 0.5
                                        context.fill(Path(ellipseIn: CGRect(x: x, y: y, width: side, height: side)),
                                                     with: .color(ZJTheme.onAccent.opacity(0.22)))
                                    }
                                }
                                .clipShape(Circle())
                            }
                            .allowsHitTesting(false)
                    }
                    .overlay { Circle().strokeBorder(ZJTheme.onAccent.opacity(0.3), lineWidth: 1) }
                Text("记一件事")
                    .font(ZJTheme.handwriting(24, relativeTo: .title3))
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

enum TodayDestination: Hashable {
    case newTask
}

private struct TodayHeader: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let date: Date
    let isEmpty: Bool
    var isDayComplete = false
    var heroHeight: CGFloat = 480

    private var greeting: String {
        switch Calendar.current.component(.hour, from: date) {
        case 5..<11: "早上好！"
        case 11..<14: "中午好！"
        case 14..<18: "下午好！"
        default: "晚上好！"
        }
    }

    var body: some View {
        Group {
            if dynamicTypeSize > .large {
                copy(scale: 1)
                    .padding(.horizontal, ZJTheme.pagePadding + 12)
                    .padding(.top, 22)
                    .padding(.bottom, 16)
            } else {
                GeometryReader { proxy in
                    let artworkWidth = min(proxy.size.width, proxy.size.height / 1.2)
                    let artworkHeight = artworkWidth * 1.2

                    // Keep the editable copy inside the illustration's empty upper-left area.
                    ZStack(alignment: .topLeading) {
                        Image("LiuliToday")
                            .resizable()
                            .scaledToFit()
                            .frame(width: artworkWidth, height: artworkHeight)
                            .accessibilityHidden(true)
                            .allowsHitTesting(false)

                        copy(scale: min(1, artworkWidth / 402))
                            .frame(width: artworkWidth * 0.48, alignment: .leading)
                            .padding(.leading, artworkWidth * 0.085)
                            .padding(.top, artworkHeight * 0.105)
                    }
                    .frame(width: artworkWidth, height: artworkHeight)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                }
                .frame(height: isEmpty ? heroHeight : 325)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func copy(scale: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(greeting)
                .font(ZJTheme.handwriting(34 * scale, relativeTo: .largeTitle).weight(.bold))
                .foregroundStyle(ZJTheme.ink)
                .accessibilityIdentifier("today.greeting")
            Text(date.formatted(.dateTime.month(.defaultDigits).day().weekday(.wide).locale(Locale(identifier: "zh_CN"))))
                .font(ZJTheme.handwriting(14 * scale, relativeTo: .subheadline))
                .foregroundStyle(ZJTheme.secondaryInk)
            Text(isDayComplete ? "今天的事都完成了，\n给自己一点休息的时间。" : "新的一天，\n从一件小事开始。")
                .font(ZJTheme.handwriting(17 * scale, relativeTo: .body))
                .lineSpacing(3)
                .foregroundStyle(ZJTheme.secondaryInk)
                .accessibilityIdentifier("today.message")
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

#Preview {
    TodayView(navigationPath: .constant([]))
        .environment(TimerController())
        .modelContainer(for: [Goal.self, TodoTask.self, TimingSession.self], inMemory: true)
}
