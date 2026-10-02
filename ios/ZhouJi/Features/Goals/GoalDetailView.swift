import SwiftData
import SwiftUI

struct GoalDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(TimerController.self) private var timer
    let goal: Goal
    @Binding var isEditingTask: Bool

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
        .onChange(of: isTaskFieldFocused) { isEditingTask = isTaskFieldFocused }
        .onDisappear {
            isTaskFieldFocused = false
            isEditingTask = false
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

    private var navigationControls: some View {
        HStack {
            GoalBackButton(label: "返回目标列表", action: dismiss.callAsFunction)
            Spacer()
            NavigationLink(value: GoalDestination.settings(goal)) {
                VStack(spacing: 2) {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 22, weight: .regular))
                    Text("设置")
                        .font(ZJTheme.handwriting(11, relativeTo: .caption2))
                }
                .foregroundStyle(ZJTheme.secondaryInk)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("目标设置")
        }
        .padding(.horizontal, ZJTheme.pagePadding)
        .padding(.vertical, 2)
        .background(ZJTheme.pageBackground)
    }

    private var taskList: some View {
        let tasks = visibleTasks

        return List {
            GoalPageHeader(title: goal.name, illustration: "LiuliReading", isCompact: false, illustrationWidth: 150)
                .listRowInsets(EdgeInsets(top: 4, leading: ZJTheme.pagePadding, bottom: 10, trailing: ZJTheme.pagePadding))
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)

            GoalProgressHeader(progress: progress)
                .padding(12)
                .goalPaperCard()
                .listRowInsets(EdgeInsets(top: 0, leading: ZJTheme.pagePadding, bottom: 14, trailing: ZJTheme.pagePadding))
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)

            Text("目标任务")
                .font(ZJTheme.handwriting(23, relativeTo: .title2).weight(.bold))
                .foregroundStyle(ZJTheme.ink)
                .accessibilityAddTraits(.isHeader)
                .listRowInsets(EdgeInsets(top: 4, leading: ZJTheme.pagePadding, bottom: 10, trailing: ZJTheme.pagePadding))
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)

            if tasks.isEmpty {
                ZJEmptyState(
                    title: "把目标变成下一步",
                    message: "从一个今天能完成的小任务开始。",
                    systemImage: "checklist"
                )
                .padding(16)
                .goalPaperCard()
                .listRowInsets(EdgeInsets(top: 0, leading: ZJTheme.pagePadding, bottom: 8, trailing: ZJTheme.pagePadding))
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            } else {
                ForEach(tasks) { task in
                    TaskRow(
                        task: task,
                        isActivelyTimed: timer.activeTaskID == task.id,
                        showsGoal: false,
                        presentation: .goal,
                        onToggleCompletion: { toggle(task) },
                        onStartTimer: { startTimer(for: task) }
                    )
                    .padding(.horizontal, 10)
                    .listRowInsets(EdgeInsets(top: 0, leading: ZJTheme.pagePadding, bottom: 0, trailing: ZJTheme.pagePadding))
                    .listRowSeparator(.hidden)
                    .listRowBackground(
                        GoalTaskCardBackground(isFirst: task.id == tasks.first?.id, isLast: task.id == tasks.last?.id)
                            .padding(.horizontal, ZJTheme.pagePadding)
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
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            VStack(alignment: .leading, spacing: 8) {
                if !isTaskFieldFocused {
                    Text("添加任务")
                        .font(ZJTheme.handwriting(20, relativeTo: .headline).weight(.bold))
                        .foregroundStyle(ZJTheme.ink)
                        .accessibilityAddTraits(.isHeader)
                }
                HStack(spacing: 0) {
                    TextField("添加一个小任务", text: $draftTitle)
                    .textFieldStyle(.plain)
                    .font(.body)
                    .foregroundStyle(ZJTheme.ink)
                    .focused($isTaskFieldFocused)
                    .submitLabel(.done)
                    .onSubmit(createTask)
                    if !draftTitle.isEmpty {
                        Button {
                            draftTitle = ""
                            isTaskFieldFocused = true
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(ZJTheme.secondaryInk.opacity(0.45))
                                .frame(width: 44, height: 44)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("清空任务名称")
                    }
                }
                .padding(.leading, 12)
                .padding(.trailing, draftTitle.isEmpty ? 12 : 0)
                .frame(minHeight: 44)
                .background(ZJTheme.background.opacity(0.45), in: RoundedRectangle(cornerRadius: ZJTheme.compactCornerRadius))
                .overlay {
                    RoundedRectangle(cornerRadius: ZJTheme.compactCornerRadius)
                        .stroke(isTaskFieldFocused ? ZJTheme.accent : ZJTheme.divider, lineWidth: 0.8)
                }

                Text("新任务会自动归属「\(goal.name)」")
                    .font(ZJTheme.handwriting(12, relativeTo: .caption))
                    .foregroundStyle(ZJTheme.secondaryInk)
                    .lineLimit(2)
                    .truncationMode(.middle)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel("新任务会自动归属「\(goal.name)」")

                GoalPrintedButton(title: "添加任务", symbol: "plus", action: createTask)
                .disabled(normalizedTitle.isEmpty)
                .accessibilityLabel("添加")
            }
            .padding(12)
            .goalPaperCard()
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
        [GridItem(.adaptive(minimum: dynamicTypeSize.isAccessibilitySize ? 130 : 72), spacing: 8)]
    }

    init(goal: Goal) {
        self.goal = goal
        _draftName = State(initialValue: goal.name)
        _selectedIcon = State(initialValue: goal.iconSelection)
    }

    var body: some View {
        ZStack {
            ZJTheme.pageBackground.ignoresSafeArea()
            GeometryReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        GoalPageHeader(
                            title: "目标设置",
                            illustration: "LiuliWriting",
                            isCompact: proxy.size.height < 420 || isNameFieldFocused,
                            illustrationWidth: 160,
                            headingIdentifier: "goal.settings.heading"
                        )
                        preview
                        nameSection
                        iconSection
                    }
                    .padding(.horizontal, ZJTheme.pagePadding)
                    .padding(.top, 8)
                    .padding(.bottom, 18)
                }
                .scrollDismissesKeyboard(.interactively)
            }
        }
        .tint(ZJTheme.accent)
        .navigationTitle("目标设置")
        .toolbar(.hidden, for: .navigationBar)
        .safeAreaInset(edge: .top, spacing: 0) {
            GoalBackButton(label: "返回目标", action: dismiss.callAsFunction)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, ZJTheme.pagePadding)
                .padding(.vertical, 2)
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
            ZJGoalIcon(iconName: resolvedIcon.rawValue, size: 48, isDecorative: false)
                .accessibilityIdentifier("goal.settings.previewIcon")
                .accessibilityLabel("当前图标，\(resolvedIcon.title)")

            VStack(alignment: .leading, spacing: 5) {
                Text(normalizedName.isEmpty ? "目标名称" : normalizedName)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(normalizedName.isEmpty ? ZJTheme.secondaryInk : ZJTheme.ink)
                    .lineLimit(2)

                Text(selectedIcon == .scope ? "根据名称推荐，也可以自己选" : "让每个目标一眼可认出")
                    .font(ZJTheme.handwriting(14, relativeTo: .subheadline))
                    .foregroundStyle(ZJTheme.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(16)
        .goalPaperCard()
    }

    private var nameSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("名称")
                .font(ZJTheme.handwriting(21, relativeTo: .headline).weight(.bold))
                .foregroundStyle(ZJTheme.ink)
                .accessibilityAddTraits(.isHeader)

            TextField("目标名称", text: $draftName)
                .textFieldStyle(.plain)
                .font(.body)
                .foregroundStyle(ZJTheme.ink)
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
                .font(ZJTheme.handwriting(21, relativeTo: .headline).weight(.bold))
                .foregroundStyle(ZJTheme.ink)
                .accessibilityAddTraits(.isHeader)

            LazyVGrid(columns: iconColumns, spacing: 8) {
                ForEach(GoalIcon.allCases) { icon in
                    let iconColor = ZJTheme.goalAccent(for: icon.rawValue)

                    Button {
                        selectedIcon = icon
                    } label: {
                        VStack(spacing: 8) {
                            if icon == .scope {
                                ZJIcon(systemName: "wand.and.stars", size: 40)
                            } else {
                                ZJGoalIcon(iconName: icon.rawValue, size: 40)
                            }
                            Text(icon.title)
                                .font(ZJTheme.handwriting(12, relativeTo: .caption))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .foregroundStyle(selectedIcon == icon ? iconColor : ZJTheme.secondaryInk)
                        .padding(.vertical, 10)
                        .padding(.horizontal, 3)
                        .frame(maxWidth: .infinity, minHeight: 82)
                        .background(selectedIcon == icon ? ZJTheme.goalSoft(for: icon.rawValue) : ZJTheme.surface)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .overlay {
                        RoundedRectangle(cornerRadius: ZJTheme.compactCornerRadius, style: .continuous)
                            .stroke(selectedIcon == icon ? iconColor.opacity(0.55) : ZJTheme.divider, lineWidth: 1)
                            .allowsHitTesting(false)
                    }
                    .overlay(alignment: .topTrailing) {
                        if selectedIcon == icon {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundStyle(iconColor)
                                .padding(5)
                                .accessibilityHidden(true)
                                .allowsHitTesting(false)
                        }
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
        GoalPrintedButton(title: "保存设置", action: save)
            .disabled(isSaveDisabled)
            .padding(.horizontal, ZJTheme.pagePadding)
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
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("已完成")
                        .font(ZJTheme.handwriting(16, relativeTo: .subheadline))
                    Text("\(progress.completed)/\(progress.total)")
                        .font(.system(.title2, design: .rounded, weight: .semibold))
                        .monospacedDigit()
                }

                Spacer(minLength: 12)

                Text("\(progress.percentage)%")
                    .font(.system(.title, design: .rounded, weight: .semibold))
                    .monospacedDigit()
            }
            .foregroundStyle(ZJTheme.ink)

            ProgressView(value: progress.fraction)
                .tint(ZJTheme.success)
                .scaleEffect(x: 1, y: 3)
                .frame(height: 12)
                .accessibilityLabel("目标进度")
                .accessibilityValue("百分之 \(progress.percentage)")
        }
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

private struct GoalBackButton: View {
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "chevron.left")
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(ZJTheme.ink)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

private struct GoalPageHeader: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let title: String
    let illustration: String
    let isCompact: Bool
    var illustrationWidth: CGFloat = 182
    var headingIdentifier = "goal.tasks.heading"

    var body: some View {
        HStack(alignment: .top, spacing: 4) {
                Text(title)
                    .font(ZJTheme.handwriting(isCompact ? 30 : 36, relativeTo: .largeTitle).weight(.bold))
                    .foregroundStyle(ZJTheme.ink)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 12)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier(headingIdentifier)
                    .accessibilityLabel(title)

                if dynamicTypeSize <= .large {
                    Image(decorative: illustration)
                        .resizable()
                        .scaledToFit()
                        .containerRelativeFrame(.horizontal) { width, _ in
                            min(isCompact ? 124 : illustrationWidth, max(0, width - ZJTheme.pagePadding * 2) * 0.5)
                        }
                        .allowsHitTesting(false)
                }
        }
        .frame(minHeight: dynamicTypeSize <= .large ? (isCompact ? 84 : illustrationWidth * 2 / 3) : nil, alignment: .top)
    }
}

private struct GoalPrintedButton: View {
    @Environment(\.isEnabled) private var isEnabled
    let title: String
    var symbol: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                if let symbol {
                    Image(systemName: symbol)
                        .font(.system(size: 21, weight: .regular))
                        .accessibilityHidden(true)
                }
                Text(title)
                    .font(ZJTheme.handwriting(21, relativeTo: .headline))
            }
            .foregroundStyle(isEnabled ? ZJTheme.onAccent : ZJTheme.secondaryInk)
            .frame(maxWidth: .infinity, minHeight: 48)
            .padding(.vertical, 2)
            .background {
                RoundedRectangle(cornerRadius: ZJTheme.cornerRadius)
                    .fill(isEnabled ? ZJTheme.accent : ZJTheme.secondaryInk.opacity(0.35))
                    .overlay {
                        if isEnabled {
                            Canvas { context, size in
                                for index in 0..<650 {
                                    let x = CGFloat((index * 73 + 19) % 997) / 997 * size.width
                                    let y = CGFloat((index * 137 + 47) % 991) / 991 * size.height
                                    let side: CGFloat = index.isMultiple(of: 5) ? 1.1 : 0.5
                                    context.fill(
                                        Path(ellipseIn: CGRect(x: x, y: y, width: side, height: side)),
                                        with: .color(ZJTheme.onAccent.opacity(0.24))
                                    )
                                }
                            }
                            .clipShape(.rect(cornerRadius: ZJTheme.cornerRadius))
                            .allowsHitTesting(false)
                        }
                    }
            }
        }
        .buttonStyle(.plain)
    }
}

private struct GoalTaskCardBackground: View {
    let isFirst: Bool
    let isLast: Bool

    var body: some View {
        let shape = UnevenRoundedRectangle(
            topLeadingRadius: isFirst ? ZJTheme.cornerRadius : 0,
            bottomLeadingRadius: isLast ? ZJTheme.cornerRadius : 0,
            bottomTrailingRadius: isLast ? ZJTheme.cornerRadius : 0,
            topTrailingRadius: isFirst ? ZJTheme.cornerRadius : 0
        )
        shape.fill(ZJTheme.surface)
            .overlay { shape.stroke(ZJTheme.divider.opacity(0.75), lineWidth: 0.8) }
            .allowsHitTesting(false)
    }
}

private extension View {
    func goalPaperCard() -> some View {
        background(ZJTheme.surface, in: RoundedRectangle(cornerRadius: ZJTheme.cornerRadius))
            .overlay {
                RoundedRectangle(cornerRadius: ZJTheme.cornerRadius)
                    .stroke(ZJTheme.divider.opacity(0.75), lineWidth: 0.8)
                    .allowsHitTesting(false)
            }
    }
}
