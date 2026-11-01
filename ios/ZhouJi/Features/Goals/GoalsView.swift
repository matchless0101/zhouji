import SwiftData
import SwiftUI

struct GoalsView: View {
    @Binding var navigationPath: [GoalDestination]
    @Environment(\.modelContext) private var modelContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @Query(
        filter: #Predicate<Goal> { $0.deletedAt == nil },
        sort: \Goal.createdAt
    )
    private var visibleGoals: [Goal]

    @State private var isAddingGoal = false
    @State private var draftName = ""
    @State private var pendingDeletion: Goal?
    @State private var presentedError: String?
    @State private var selectedFilter: GoalFilter = .all
    @FocusState private var isGoalFieldFocused: Bool

    private var inProgressGoals: [Goal] {
        visibleGoals.filter { goal in
            let progress = GoalService.progress(for: goal)
            return progress.total == 0 || progress.completed < progress.total
        }
    }

    private var completedGoals: [Goal] {
        visibleGoals.filter { goal in
            let progress = GoalService.progress(for: goal)
            return progress.total > 0 && progress.completed == progress.total
        }
    }

    private var filteredGoals: [Goal] {
        switch selectedFilter {
        case .all:
            visibleGoals
        case .inProgress:
            inProgressGoals
        case .completed:
            completedGoals
        }
    }

    var body: some View {
        NavigationStack(path: $navigationPath) {
            ZStack {
                List {
                    if filteredGoals.isEmpty {
                        ZJEmptyState(
                            title: visibleGoals.isEmpty ? "想持续推进什么？" : "这里还没有目标",
                            message: visibleGoals.isEmpty ? "先写下一个目标，再用每天的小任务慢慢靠近。" : "换个分类看看，或继续推进现有目标。",
                            systemImage: visibleGoals.isEmpty ? "scope" : "line.3.horizontal.decrease"
                        )
                        .padding(18)
                        .zjCard()
                        .listRowInsets(EdgeInsets(top: 6, leading: ZJTheme.pagePadding + 6, bottom: 6, trailing: ZJTheme.pagePadding + 6))
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                    } else {
                        goalGrid
                            .listRowInsets(EdgeInsets(top: 6, leading: ZJTheme.pagePadding + 2, bottom: 6, trailing: ZJTheme.pagePadding + 2))
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                    }
                }
                .listStyle(.plain)
                .contentMargins(.top, 0, for: .scrollContent)
                .contentMargins(.bottom, 16, for: .scrollContent)
                .scrollContentBackground(.hidden)
                .clipped()
            }
            .toolbar(.hidden, for: .navigationBar)
            .safeAreaInset(edge: .top, spacing: 0) {
                // A black card below the status bar keeps the system time readable.
                pageHeader
                    .padding(.horizontal, 20)
                    .padding(.top, 14)
                    .padding(.bottom, 20)
                    .background(ZJInkBlock(cornerRadius: 30))
                    .padding(.horizontal, ZJTheme.pagePadding)
                    .padding(.top, 6)
                    .padding(.bottom, 10)
                    .background(ZJTheme.pageBackground)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if isAddingGoal { addGoalControls }
            }
            .background(ZJTheme.pageBackground.ignoresSafeArea())
            .navigationDestination(for: GoalDestination.self) { destination in
                switch destination {
                case .tasks(let goal):
                    GoalDetailView(goal: goal)
                case .settings(let goal):
                    GoalSettingsView(goal: goal)
                }
            }
            .confirmationDialog(
                "删除“\(pendingDeletion?.name ?? "这个目标")”？",
                isPresented: Binding(
                    get: { pendingDeletion != nil },
                    set: { if !$0 { pendingDeletion = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("删除目标", role: .destructive) {
                    deletePendingGoal()
                }
                Button("取消", role: .cancel) {
                    pendingDeletion = nil
                }
            } message: {
                Text("其中的任务会保留，但不再属于这个目标。")
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
        }
    }

    /// A black header carries the motto, the filter and the new-goal button.
    private var pageHeader: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center) {
                Text("目标 · \(visibleGoals.count)")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(ZJTheme.secondaryOnEmphasis)
                Spacer(minLength: 8)
                if !isAddingGoal {
                    Button(action: beginCreatingGoal) {
                        Image(systemName: "plus")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(ZJTheme.ink)
                            .frame(width: 44, height: 44)
                            .background(ZJTheme.surface, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("新建目标")
                } else {
                    Color.clear.frame(width: 44, height: 44)
                }
            }
            Text(dynamicTypeSize.isAccessibilitySize ? "慢一点，但一直向前。" : "慢一点，\n但一直向前。")
                .font(.title2.weight(.bold))
                .lineSpacing(4)
                .foregroundStyle(ZJTheme.onEmphasis)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            Menu {
                ForEach(GoalFilter.allCases, id: \.self) { filter in
                    Button { selectedFilter = filter } label: {
                        if selectedFilter == filter {
                            Label(filter.title, systemImage: "checkmark")
                        } else {
                            Text(filter.title)
                        }
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    Text("我的目标 · \(selectedFilter.title)")
                        .font(.subheadline.weight(.medium))
                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.bold))
                }
                .foregroundStyle(ZJTheme.onEmphasis)
                .padding(.horizontal, 14)
                .frame(minHeight: 36)
                .background(ZJTheme.onEmphasis.opacity(0.12), in: Capsule())
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .accessibilityLabel("我的目标，筛选目标")
            .accessibilityIdentifier("目标筛选")
            .accessibilityValue(selectedFilter.title)
            .accessibilityHint("选择全部、进行中或已完成目标")
        }
    }

    /// Goals are two-column cards; deletion lives in the long-press menu and a VoiceOver action.
    private var goalGrid: some View {
        let columnCount = dynamicTypeSize.isAccessibilitySize ? 1 : 2
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: columnCount), spacing: 12) {
            ForEach(Array(filteredGoals.enumerated()), id: \.element.id) { index, goal in
                Button {
                    navigationPath.append(.tasks(goal))
                } label: {
                    GoalCard(goal: goal, number: index + 1)
                }
                .buttonStyle(.plain)
                .contextMenu {
                    Button(role: .destructive) {
                        pendingDeletion = goal
                    } label: {
                        Label("删除", systemImage: "trash")
                    }
                }
                .accessibilityAction(named: "删除") { pendingDeletion = goal }
            }
        }
    }

    private var addGoalControls: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                TextField("目标名称", text: $draftName)
                    .textFieldStyle(.plain)
                    .focused($isGoalFieldFocused)
                    .submitLabel(.done)
                    .onSubmit(createGoal)
                    .padding(.horizontal, 14)
                    .frame(minHeight: ZJTheme.controlHeight)
                    .background(ZJTheme.mutedSurface, in: RoundedRectangle(cornerRadius: ZJTheme.compactCornerRadius))

                Button("取消") { cancelCreatingGoal() }
                    .foregroundStyle(ZJTheme.secondaryInk)

                Button("创建") { createGoal() }
                    .fontWeight(.semibold)
                    .foregroundStyle(normalizedDraftName.isEmpty ? ZJTheme.secondaryInk.opacity(0.45) : ZJTheme.accent)
                    .disabled(normalizedDraftName.isEmpty)
            }
            .padding(12)
            .zjCard()
            .padding(.horizontal, ZJTheme.pagePadding)
        }
        .padding(.top, 8)
        .padding(.bottom, 8)
        .background(Color.clear)
    }

    private func beginCreatingGoal() {
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) {
            isAddingGoal = true
        }
        isGoalFieldFocused = true
    }

    private var normalizedDraftName: String {
        draftName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func createGoal() {
        do {
            _ = try GoalService.create(name: draftName, in: modelContext)
            draftName = ""
            isAddingGoal = false
            isGoalFieldFocused = false
        } catch {
            presentedError = error.localizedDescription
        }
    }

    private func cancelCreatingGoal() {
        draftName = ""
        isAddingGoal = false
        isGoalFieldFocused = false
    }

    private func deletePendingGoal() {
        guard let goal = pendingDeletion else { return }
        do {
            try GoalService.softDelete(goal, in: modelContext)
            pendingDeletion = nil
        } catch {
            presentedError = error.localizedDescription
        }
    }
}

private enum GoalFilter: CaseIterable, Hashable {
    case all
    case inProgress
    case completed

    var title: String {
        switch self {
        case .all: "全部"
        case .inProgress: "进行中"
        case .completed: "已完成"
        }
    }
}

private struct GoalCard: View {
    let goal: Goal
    let number: Int
    private var progress: GoalProgress { GoalService.progress(for: goal) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                ZJIcon(systemName: goal.displayIconName, size: 44, tint: ZJTheme.onAccent)
                    .background(ZJTheme.accent, in: Circle())
                Spacer(minLength: 8)
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(ZJTheme.ink)
                    .frame(width: 32, height: 32)
                    .background(ZJTheme.mutedSurface, in: Circle())
                    .accessibilityHidden(true)
            }
            Spacer(minLength: 18)
            Text(String(format: "G-%02d", number))
                .font(.caption2.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(ZJTheme.secondaryInk)
                .padding(.bottom, 4)
            Text(goal.name)
                .font(.headline.weight(.bold))
                .foregroundStyle(ZJTheme.ink)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 150, alignment: .topLeading)
        .zjCard()
        .contentShape(RoundedRectangle(cornerRadius: ZJTheme.cornerRadius, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(goal.name)
        .accessibilityValue("完成 \(progress.completed) 个，共 \(progress.total) 个任务，进度百分之 \(progress.percentage)")
    }
}

