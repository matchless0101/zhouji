import SwiftData
import SwiftUI

struct GoalDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(TimerController.self) private var timer
    let goal: Goal

    @State private var draftTitle = ""
    @State private var isTimerPresented = false
    @State private var pendingTimerTask: TodoTask?
    @State private var undoCandidate: TodoTask?
    @State private var undoDismissTask: Task<Void, Never>?
    @State private var presentedError: String?
    @FocusState private var isTaskFieldFocused: Bool

    private var progress: GoalProgress {
        GoalService.progress(for: goal)
    }

    private var visibleTasks: [TodoTask] {
        goal.tasks
            .filter { $0.deletedAt == nil }
            .sorted { lhs, rhs in
                if lhs.isCompleted != rhs.isCompleted {
                    return !lhs.isCompleted
                }
                return lhs.createdAt < rhs.createdAt
            }
    }

    var body: some View {
        ZStack {
            ZJTheme.pageBackground.ignoresSafeArea()

            List {
                GoalProgressHeader(progress: progress, iconName: goal.displayIconName)
                    .padding(18)
                    .zjCard()
                    .listRowInsets(EdgeInsets(top: 14, leading: ZJTheme.pagePadding, bottom: 24, trailing: ZJTheme.pagePadding))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)

                if visibleTasks.isEmpty {
                    ZJEmptyState(
                        title: "把目标变成下一步",
                        message: "从一个今天能完成的小任务开始。",
                        systemImage: "checklist"
                    )
                        .padding(18)
                        .zjCard()
                        .listRowInsets(EdgeInsets(top: 30, leading: ZJTheme.pagePadding, bottom: 30, trailing: ZJTheme.pagePadding))
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                } else {
                    ForEach(visibleTasks) { task in
                        TaskRow(
                            task: task,
                            isActivelyTimed: timer.activeTaskID == task.id,
                            showsGoal: false,
                            onToggleCompletion: { toggle(task) },
                            onStartTimer: { startTimer(for: task) }
                        )
                            .listRowInsets(EdgeInsets(top: 0, leading: ZJTheme.pagePadding, bottom: 0, trailing: ZJTheme.pagePadding))
                            .listRowSeparatorTint(ZJTheme.divider)
                            .listRowBackground(Color.clear)
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    delete(task)
                                } label: {
                                    Label("删除", systemImage: "trash")
                                }
                            }
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
        .navigationTitle(goal.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(ZJTheme.surface.opacity(0.96), for: .navigationBar)
        .toolbar(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink {
                    GoalSettingsView(goal: goal)
                } label: {
                    Image(systemName: "slider.horizontal.3")
                }
                .accessibilityLabel("目标设置")
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            addTaskBar
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
            if let pendingTimerTask,
               let currentTitle = timer.activeSession?.taskTitleSnapshot {
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
            Button("好", role: .cancel) { presentedError = nil }
        } message: {
            Text(presentedError ?? "请稍后重试。")
        }
        .onDisappear {
            undoDismissTask?.cancel()
        }
    }

    private var addTaskBar: some View {
        VStack(spacing: 0) {
            if let undoCandidate {
                TaskUndoToast(
                    taskTitle: undoCandidate.title,
                    onUndo: { undoDelete(undoCandidate) }
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            Divider().overlay(ZJTheme.divider)
            HStack(spacing: 10) {
                TextField("添加一个小任务", text: $draftTitle)
                    .textFieldStyle(.plain)
                    .focused($isTaskFieldFocused)
                    .submitLabel(.done)
                    .onSubmit(createTask)
                    .padding(.horizontal, 14)
                    .frame(minHeight: ZJTheme.controlHeight)
                    .background(ZJTheme.background, in: RoundedRectangle(cornerRadius: ZJTheme.compactCornerRadius))

                Button("添加") {
                    createTask()
                }
                .fontWeight(.semibold)
                .foregroundStyle(normalizedTitle.isEmpty ? ZJTheme.secondaryInk.opacity(0.45) : ZJTheme.accent)
                .disabled(normalizedTitle.isEmpty)
            }
            .padding(.horizontal, ZJTheme.pagePadding)
            .padding(.vertical, 10)
        }
        .background(ZJTheme.surface)
    }

    private var normalizedTitle: String {
        draftTitle.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func createTask() {
        do {
            _ = try TaskService.create(title: draftTitle, goal: goal, in: modelContext)
            draftTitle = ""
            isTaskFieldFocused = false
        } catch {
            presentedError = error.localizedDescription
        }
    }

    private func toggle(_ task: TodoTask) {
        if !task.isCompleted, timer.activeTaskID == task.id {
            guard timer.finishActiveSession() else {
                presentedError = timer.errorMessage
                timer.clearError()
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

private struct GoalSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let goal: Goal

    @State private var draftName: String
    @State private var selectedIcon: GoalIcon
    @State private var presentedError: String?
    @FocusState private var isNameFieldFocused: Bool

    private let iconColumns = [
        GridItem(.adaptive(minimum: 72), spacing: 10)
    ]

    init(goal: Goal) {
        self.goal = goal
        _draftName = State(initialValue: goal.name)
        _selectedIcon = State(initialValue: goal.icon)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                preview
                nameSection
                iconSection
            }
            .padding(.horizontal, ZJTheme.pagePadding)
            .padding(.top, 18)
            .padding(.bottom, 36)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(ZJTheme.pageBackground.ignoresSafeArea())
        .navigationTitle("目标设置")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(ZJTheme.background, for: .navigationBar)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            saveBar
        }
        .alert(
            "保存失败",
            isPresented: Binding(
                get: { presentedError != nil },
                set: { if !$0 { presentedError = nil } }
            )
        ) {
            Button("好", role: .cancel) { presentedError = nil }
        } message: {
            Text(presentedError ?? "请稍后重试。")
        }
    }

    private var preview: some View {
        let iconColor = ZJTheme.goalAccent(for: selectedIcon.rawValue)

        return HStack(spacing: 16) {
            Image(systemName: selectedIcon.rawValue)
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(iconColor)
                .frame(width: 58, height: 58)
                .background(ZJTheme.goalSoft(for: selectedIcon.rawValue), in: RoundedRectangle(cornerRadius: 17, style: .continuous))
                .accessibilityIdentifier("goal.settings.previewIcon")
                .accessibilityLabel("当前图标，\(selectedIcon.title)")

            VStack(alignment: .leading, spacing: 5) {
                Text(normalizedName.isEmpty ? "目标名称" : normalizedName)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(normalizedName.isEmpty ? ZJTheme.secondaryInk : ZJTheme.ink)
                    .lineLimit(2)

                Text("让每个目标一眼可认出")
                    .font(.subheadline)
                    .foregroundStyle(ZJTheme.secondaryInk)
            }

            Spacer(minLength: 0)
        }
        .padding(18)
        .zjCard()
    }

    private var nameSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("名称")
                .font(.headline)
                .foregroundStyle(ZJTheme.ink)

            TextField("目标名称", text: $draftName)
                .textFieldStyle(.plain)
                .focused($isNameFieldFocused)
                .submitLabel(.done)
                .onSubmit(save)
                .padding(.horizontal, 16)
                .frame(minHeight: 52)
                .background(ZJTheme.surface, in: RoundedRectangle(cornerRadius: ZJTheme.compactCornerRadius, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: ZJTheme.compactCornerRadius, style: .continuous)
                        .stroke(isNameFieldFocused ? ZJTheme.accent : ZJTheme.divider, lineWidth: 1)
                }
        }
    }

    private var iconSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("图标")
                .font(.headline)
                .foregroundStyle(ZJTheme.ink)

            LazyVGrid(columns: iconColumns, spacing: 10) {
                ForEach(GoalIcon.allCases) { icon in
                    let iconColor = ZJTheme.goalAccent(for: icon.rawValue)

                    Button {
                        selectedIcon = icon
                    } label: {
                        VStack(spacing: 8) {
                            Image(systemName: icon.rawValue)
                                .font(.system(size: 20, weight: .semibold))
                            Text(icon.title)
                                .font(.caption)
                                .lineLimit(1)
                        }
                        .foregroundStyle(selectedIcon == icon ? iconColor : ZJTheme.secondaryInk)
                        .frame(maxWidth: .infinity, minHeight: 70)
                        .background(selectedIcon == icon ? ZJTheme.goalSoft(for: icon.rawValue) : Color.clear)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .overlay {
                        RoundedRectangle(cornerRadius: ZJTheme.compactCornerRadius, style: .continuous)
                            .stroke(selectedIcon == icon ? iconColor.opacity(0.55) : ZJTheme.divider, lineWidth: 1)
                    }
                    .compositingGroup()
                    .clipShape(RoundedRectangle(cornerRadius: ZJTheme.compactCornerRadius, style: .continuous))
                    .accessibilityIdentifier("goal.icon.\(icon.rawValue)")
                    .accessibilityLabel(icon.title)
                    .accessibilityAddTraits(selectedIcon == icon ? .isSelected : [])
                }
            }
        }
    }

    private var saveBar: some View {
        Button("保存设置", action: save)
            .font(.headline)
            .frame(maxWidth: .infinity, minHeight: ZJTheme.controlHeight)
            .buttonStyle(.zjPrimary)
            .disabled(isSaveDisabled)
            .padding(.horizontal, ZJTheme.pagePadding)
            .padding(.vertical, 8)
            .background(ZJTheme.background)
    }

    private var normalizedName: String {
        draftName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isSaveDisabled: Bool {
        normalizedName.isEmpty || (normalizedName == goal.name && selectedIcon == goal.icon)
    }

    private func save() {
        guard !normalizedName.isEmpty else { return }
        do {
            try GoalService.update(
                goal,
                name: draftName,
                icon: selectedIcon,
                in: modelContext
            )
            dismiss()
        } catch {
            presentedError = error.localizedDescription
        }
    }
}

private struct GoalProgressHeader: View {
    let progress: GoalProgress
    let iconName: String

    var body: some View {
        let goalColor = ZJTheme.goalAccent(for: iconName)

        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Label("目标进度", systemImage: iconName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(goalColor)

                Spacer(minLength: 12)

                Text(progress.percentage, format: .percent.scale(1))
                    .font(.title2.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(goalColor)
            }

            ProgressView(value: progress.fraction)
                .tint(goalColor)
                .accessibilityLabel("目标进度")
                .accessibilityValue("百分之 \(progress.percentage)")

            Text("已完成 \(progress.completed) 件，共 \(progress.total) 件")
                .font(.caption)
                .foregroundStyle(ZJTheme.secondaryInk)
        }
    }
}
