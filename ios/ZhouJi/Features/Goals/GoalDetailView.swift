import SwiftData
import SwiftUI

struct GoalDetailView: View {
    @Environment(\.dismiss) private var dismiss
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

            taskList
        }
        .tint(ZJTheme.accent)
        .navigationTitle(goal.name)
        .toolbar(.hidden, for: .navigationBar)
        .safeAreaInset(edge: .top, spacing: 0) {
            navigationControls
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            addTaskBar
        }
        .onDisappear {
            isTaskFieldFocused = false
        }
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
            Button("好", role: .cancel) { presentedError = nil }
        } message: {
            Text(presentedError ?? "请稍后重试。")
        }
        .onDisappear {
            undoDismissTask?.cancel()
        }
    }

    private var navigationControls: some View {
        ZStack {
            Text(goal.name)
                .font(.headline.weight(.bold))
                .foregroundStyle(ZJTheme.ink)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 56)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("goal.tasks.heading")
                .accessibilityLabel(goal.name)
            HStack {
                ZJBackButton(label: "返回目标列表", action: dismiss.callAsFunction)
                Spacer()
                NavigationLink(value: GoalDestination.settings(goal)) {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(ZJTheme.ink)
                        .frame(width: 44, height: 44)
                        .background(ZJTheme.surface, in: Circle())
                        .compositingGroup()
                        .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 4)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("目标设置")
            }
        }
        .padding(.horizontal, ZJTheme.pagePadding)
        .padding(.top, 4)
        .padding(.bottom, 6)
        .background(ZJTheme.pageBackground)
    }

    private var taskList: some View {
        let tasks = visibleTasks

        return List {
            GoalProgressHeader(progress: progress)
                .padding(.horizontal, 22)
                .padding(.vertical, 20)
                .background(ZJInkBlock())
                .listRowInsets(EdgeInsets(top: 10, leading: ZJTheme.pagePadding, bottom: 14, trailing: ZJTheme.pagePadding))
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)

            ZJSectionHeader(title: "任务", count: tasks.count)
                .accessibilityAddTraits(.isHeader)
                .listRowInsets(EdgeInsets(top: 4, leading: ZJTheme.pagePadding + 2, bottom: 6, trailing: ZJTheme.pagePadding + 2))
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)

            if tasks.isEmpty {
                ZJEmptyState(
                    title: "把目标变成下一步",
                    message: "从一个今天能完成的小任务开始。",
                    systemImage: "checklist"
                )
                .padding(16)
                .zjCard()
                .listRowInsets(EdgeInsets(top: 0, leading: ZJTheme.pagePadding, bottom: 8, trailing: ZJTheme.pagePadding))
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            } else {
                ForEach(tasks) { task in
                    GoalTimelineRow(
                        task: task,
                        isActivelyTimed: timer.activeTaskID == task.id,
                        onToggleCompletion: { toggle(task) },
                        onStartTimer: { startTimer(for: task) }
                    )
                    .listRowInsets(EdgeInsets(top: 4, leading: ZJTheme.pagePadding, bottom: 4, trailing: ZJTheme.pagePadding))
                    .listRowSeparator(.hidden)
                    .listRowBackground(
                        GoalTimelineLine(isFirst: task.id == tasks.first?.id, isLast: task.id == tasks.last?.id)
                    )
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) { delete(task) } label: {
                            Label("删除", systemImage: "trash")
                        }
                    }
                }
            }
        }
        .listStyle(.plain)
        .listRowSpacing(0)
        .environment(\.defaultMinListRowHeight, 44)
        .contentMargins(.top, 0, for: .scrollContent)
        .contentMargins(.bottom, 8, for: .scrollContent)
        .scrollContentBackground(.hidden)
        .scrollDismissesKeyboard(.interactively)
    }

    private var addTaskBar: some View {
        VStack(spacing: 0) {
            if let undoCandidate {
                TaskUndoToast(
                    taskTitle: undoCandidate.title,
                    onUndo: { undoDelete(undoCandidate) }
                )
                .id(undoCandidate.id)
                .padding(.top, 4)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            HStack(spacing: 8) {
                TextField("记一件事 · 自动归属「\(goal.name)」", text: $draftTitle)
                    .textFieldStyle(.plain)
                    .font(.body)
                    .foregroundStyle(ZJTheme.ink)
                    .focused($isTaskFieldFocused)
                    .submitLabel(.done)
                    .onSubmit(createTask)
                    .accessibilityIdentifier("goal.newTask")
                    .accessibilityLabel("新任务会自动归属「\(goal.name)」")
                if !draftTitle.isEmpty {
                    Button {
                        draftTitle = ""
                        isTaskFieldFocused = true
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(ZJTheme.secondaryInk)
                            .frame(width: 28, height: 28)
                            .background(ZJTheme.mutedSurface, in: Circle())
                            .frame(width: 36, height: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("清空任务名称")
                }
                Button(action: createTask) {
                    Image(systemName: "plus")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(normalizedTitle.isEmpty ? ZJTheme.secondaryInk : ZJTheme.onAccent)
                        .frame(width: 44, height: 44)
                        .background(normalizedTitle.isEmpty ? ZJTheme.mutedSurface : ZJTheme.accent, in: Circle())
                }
                .buttonStyle(.plain)
                .disabled(normalizedTitle.isEmpty)
                .accessibilityLabel("添加")
            }
            .padding(.leading, 20)
            .padding(.trailing, 6)
            .frame(minHeight: 56)
            .background(ZJTheme.surface, in: Capsule())
            .compositingGroup()
            .shadow(color: .black.opacity(0.08), radius: 14, x: 0, y: 6)
            .padding(.horizontal, ZJTheme.pagePadding)
            .padding(.vertical, 8)
        }
        .background(ZJTheme.pageBackground)
    }

    private var normalizedTitle: String {
        draftTitle.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func createTask() {
        guard !normalizedTitle.isEmpty else { return }
        do {
            _ = try TaskService.create(title: draftTitle, goal: goal, in: modelContext)
            draftTitle = ""
            isTaskFieldFocused = false
        } catch {
            presentedError = error.localizedDescription
        }
    }

    private func toggle(_ task: TodoTask) {
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

struct GoalSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let goal: Goal

    @State private var draftName: String
    @State private var selectedIcon: GoalIcon
    @State private var presentedError: String?
    @FocusState private var isNameFieldFocused: Bool

    private var iconColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 10), count: dynamicTypeSize.isAccessibilitySize ? 2 : 4)
    }

    init(goal: Goal) {
        self.goal = goal
        _draftName = State(initialValue: goal.name)
        _selectedIcon = State(initialValue: goal.iconSelection)
    }

    var body: some View {
        ZStack {
            ZJTheme.pageBackground.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    preview
                    nameSection
                    iconSection
                }
                .padding(.horizontal, ZJTheme.pagePadding + 2)
                .padding(.top, 8)
                .padding(.bottom, 18)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .tint(ZJTheme.accent)
        .navigationTitle("目标设置")
        .toolbar(.hidden, for: .navigationBar)
        .safeAreaInset(edge: .top, spacing: 0) {
            ZStack {
                Text("目标设置")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(ZJTheme.ink)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("goal.settings.heading")
                ZJBackButton(label: "返回目标", action: dismiss.callAsFunction)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, ZJTheme.pagePadding)
            .padding(.top, 4)
            .padding(.bottom, 6)
            .background(ZJTheme.pageBackground)
        }
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
        let resolvedIcon = selectedIcon.resolved(for: draftName)

        return HStack(spacing: 16) {
            ZJGoalIcon(iconName: resolvedIcon.rawValue, size: 46, isDecorative: false)
                .foregroundStyle(ZJTheme.ink)
                .frame(width: 60, height: 60)
                .background(ZJTheme.onEmphasis, in: Circle())
                .accessibilityIdentifier("goal.settings.previewIcon")
                .accessibilityLabel("当前图标，\(resolvedIcon.title)")

            VStack(alignment: .leading, spacing: 4) {
                Text("预览")
                    .font(.caption)
                    .foregroundStyle(ZJTheme.secondaryOnEmphasis)
                Text(normalizedName.isEmpty ? "目标名称" : normalizedName)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(normalizedName.isEmpty ? ZJTheme.secondaryOnEmphasis : ZJTheme.onEmphasis)
                    .lineLimit(2)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .frame(minHeight: 112)
        .background(ZJInkBlock())
    }

    private var nameSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("目标名称")
                .font(.caption.weight(.medium))
                .foregroundStyle(ZJTheme.secondaryInk)
            TextField("目标名称", text: $draftName)
                .textFieldStyle(.plain)
                .font(.title3.weight(.semibold))
                .foregroundStyle(ZJTheme.ink)
                .focused($isNameFieldFocused)
                .submitLabel(.done)
                .onSubmit(save)
                .frame(minHeight: 36)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .zjCard()
    }

    private var iconSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("图标")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(ZJTheme.ink)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 8)
                Text("自动匹配会按名称推荐")
                    .font(.caption)
                    .foregroundStyle(ZJTheme.secondaryInk)
            }
            .padding(.top, 6)
            .padding(.horizontal, 2)

            LazyVGrid(columns: iconColumns, spacing: 10) {
                ForEach(GoalIcon.allCases) { icon in
                    let isSelected = selectedIcon == icon
                    Button {
                        selectedIcon = icon
                    } label: {
                        VStack(spacing: 6) {
                            ZJIcon(systemName: icon == .scope ? "wand.and.stars" : ZJTheme.goalSymbol(for: icon.rawValue),
                                   size: 36, tint: isSelected ? ZJTheme.onAccent : ZJTheme.ink)
                            Text(icon.title)
                                .font(.caption2.weight(.semibold))
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                                .foregroundStyle(isSelected ? ZJTheme.onAccent : ZJTheme.ink)
                        }
                        .frame(maxWidth: .infinity, minHeight: 76)
                        .background {
                            RoundedRectangle(cornerRadius: 22, style: .continuous)
                                .fill(isSelected ? ZJTheme.accent : ZJTheme.surface)
                                .shadow(color: .black.opacity(isSelected ? 0.2 : 0.05), radius: isSelected ? 10 : 8, x: 0, y: 4)
                        }
                        .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("goal.icon.\(icon.rawValue)")
                    .accessibilityLabel(icon.title)
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
        }
    }

    private var saveBar: some View {
        VStack(spacing: 8) {
            GoalPrimaryButton(title: "保存设置", action: save)
                .disabled(isSaveDisabled)
            Text(isSaveDisabled ? "名称和图标都未改动，暂不可保存" : "直接返回不会保存草稿")
                .font(.caption)
                .foregroundStyle(ZJTheme.secondaryInk)
        }
        .padding(.horizontal, ZJTheme.pagePadding + 2)
        .padding(.vertical, 8)
        .background(ZJTheme.pageBackground)
    }

    private var normalizedName: String {
        draftName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isSaveDisabled: Bool {
        normalizedName.isEmpty || (normalizedName == goal.name && selectedIcon == goal.iconSelection)
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

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("自动进度")
                        .font(.caption)
                        .foregroundStyle(ZJTheme.secondaryOnEmphasis)
                    Text("\(progress.percentage)") + Text("%").font(.system(size: 22, weight: .regular))
                }
                .font(.system(size: 52, weight: .light, design: ZJTheme.numberDesign))
                .monospacedDigit()
                Spacer(minLength: 12)
                Text("\(progress.completed)/\(progress.total)")
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
                    .padding(.horizontal, 12)
                    .frame(minHeight: 28)
                    .background(ZJTheme.onEmphasis.opacity(0.12), in: Capsule())
            }
            .foregroundStyle(ZJTheme.onEmphasis)
            progressBar
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("目标进度")
    }

    /// One segment per task while that stays readable; larger goals fall back to a continuous bar.
    @ViewBuilder
    private var progressBar: some View {
        if (1...12).contains(progress.total) {
            HStack(spacing: 5) {
                ForEach(0..<progress.total, id: \.self) { index in
                    Capsule()
                        .fill(index < progress.completed ? ZJTheme.onEmphasis : ZJTheme.onEmphasis.opacity(0.18))
                        .frame(height: 6)
                }
            }
        } else {
            Capsule()
                .fill(ZJTheme.onEmphasis.opacity(0.18))
                .frame(height: 6)
                .overlay(alignment: .leading) {
                    GeometryReader { proxy in
                        Capsule()
                            .fill(ZJTheme.onEmphasis)
                            .frame(width: proxy.size.width * progress.fraction)
                    }
                }
        }
    }
}

/// A goal task on the timeline: a node to complete it, then a white card with the timer.
private struct GoalTimelineRow: View {
    let task: TodoTask
    let isActivelyTimed: Bool
    let onToggleCompletion: () -> Void
    let onStartTimer: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button(action: onToggleCompletion) {
                Group {
                    if task.isCompleted {
                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(ZJTheme.onAccent)
                            .frame(width: 22, height: 22)
                            .background(ZJTheme.accent, in: Circle())
                    } else {
                        Circle()
                            .strokeBorder(ZJTheme.ink, lineWidth: 1.6)
                            .background(Circle().fill(ZJTheme.background))
                            .frame(width: 16, height: 16)
                    }
                }
                .frame(width: 24, height: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(task.isCompleted ? "恢复任务" : "完成任务")
            .accessibilityHint(task.title)

            if task.isCompleted {
                Text(task.title)
                    .font(.subheadline)
                    .foregroundStyle(ZJTheme.secondaryInk)
                    .strikethrough(true, color: ZJTheme.secondaryInk)
                    .lineLimit(3)
                    .padding(.leading, 16)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                HStack(spacing: 10) {
                    Text(task.title)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(ZJTheme.ink)
                        .lineLimit(3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button(action: onStartTimer) {
                        Image(systemName: isActivelyTimed ? "waveform" : "play.fill")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(isActivelyTimed ? ZJTheme.onAccent : ZJTheme.ink)
                            .frame(width: 40, height: 40)
                            .background(isActivelyTimed ? ZJTheme.accent : ZJTheme.mutedSurface, in: Circle())
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(isActivelyTimed ? "查看计时" : "开始计时")
                    .accessibilityHint(task.title)
                }
                .padding(.leading, 16)
                .padding(.trailing, 8)
                .padding(.vertical, 6)
                .frame(minHeight: 60)
                .background {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(ZJTheme.surface)
                        .shadow(color: .black.opacity(0.05), radius: 10, x: 0, y: 4)
                }
            }
        }
    }
}

/// The vertical rule behind the timeline nodes; it starts and ends at the first and last node.
private struct GoalTimelineLine: View {
    let isFirst: Bool
    let isLast: Bool

    var body: some View {
        GeometryReader { proxy in
            let mid = proxy.size.height / 2
            Rectangle()
                .fill(ZJTheme.secondaryInk.opacity(0.28))
                .frame(width: 1.5, height: max(0, (isLast ? mid : proxy.size.height) - (isFirst ? mid : 0)))
                .offset(x: ZJTheme.pagePadding + 11.25, y: isFirst ? mid : 0)
        }
        .allowsHitTesting(false)
    }
}

enum GoalDestination: Hashable {
    case tasks(Goal)
    case settings(Goal)

    var isSettings: Bool {
        if case .settings = self { return true }
        return false
    }
}

private struct GoalPrimaryButton: View {
    let title: String
    var symbol: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                if let symbol {
                    Image(systemName: symbol)
                        .font(.system(size: 18, weight: .semibold))
                        .accessibilityHidden(true)
                }
                Text(title)
            }
        }
        .buttonStyle(ZJPrimaryButtonStyle())
    }
}

