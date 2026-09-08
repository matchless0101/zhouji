import SwiftData
import SwiftUI

struct GoalsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @Query(sort: \Goal.createdAt)
    private var allGoals: [Goal]

    @State private var isAddingGoal = false
    @State private var draftName = ""
    @State private var pendingDeletion: Goal?
    @State private var presentedError: String?
    @State private var selectedFilter: GoalFilter = .all
    @FocusState private var isGoalFieldFocused: Bool

    private var visibleGoals: [Goal] {
        allGoals.filter { $0.deletedAt == nil }
    }

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
        NavigationStack {
            ZStack {
                ZJTheme.background.ignoresSafeArea()

                List {
                    pageHeader
                        .listRowInsets(EdgeInsets(top: 12, leading: ZJTheme.pagePadding, bottom: 12, trailing: ZJTheme.pagePadding))
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)

                    filterBar
                        .listRowInsets(EdgeInsets(top: 0, leading: ZJTheme.pagePadding, bottom: 12, trailing: ZJTheme.pagePadding))
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)

                    if filteredGoals.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(visibleGoals.isEmpty ? "想持续推进什么？" : "这里还没有目标")
                                .font(.title3.weight(.semibold))
                                .foregroundStyle(ZJTheme.ink)
                            Text(visibleGoals.isEmpty ? "先写下一个目标，再用每天的小任务慢慢靠近。" : "换个分类看看，或继续推进现有目标。")
                                .font(.body)
                                .foregroundStyle(ZJTheme.secondaryInk)
                        }
                        .padding(18)
                        .zjCard()
                        .listRowInsets(EdgeInsets(top: 8, leading: ZJTheme.pagePadding, bottom: 8, trailing: ZJTheme.pagePadding))
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                    } else {
                        ForEach(filteredGoals) { goal in
                            NavigationLink {
                                GoalDetailView(goal: goal)
                            } label: {
                                GoalRow(goal: goal)
                            }
                            .buttonStyle(.plain)
                            .listRowInsets(EdgeInsets(top: 6, leading: ZJTheme.pagePadding, bottom: 6, trailing: ZJTheme.pagePadding))
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                            .swipeActions {
                                Button(role: .destructive) {
                                    pendingDeletion = goal
                                } label: {
                                    Label("删除", systemImage: "trash")
                                }
                            }
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .background(Color.clear)
            }
            .toolbar(.hidden, for: .navigationBar)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                addGoalControls
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

    private var pageHeader: some View {
        VStack(alignment: .leading, spacing: 24) {
            ZJBrandHeader(
                subtitle: "小小的目标，汇聚成大的改变。",
                systemImage: "plus.circle",
                actionLabel: "快速新建目标",
                action: beginCreatingGoal
            )

            Text("目标")
                .font(.system(.largeTitle, design: .rounded, weight: .bold))
                .foregroundStyle(ZJTheme.ink)
        }
    }

    private var filterBar: some View {
        HStack(spacing: 4) {
            filterButton(.all, count: visibleGoals.count)
            filterButton(.inProgress, count: inProgressGoals.count)
            filterButton(.completed, count: completedGoals.count)
        }
        .padding(4)
        .background(ZJTheme.mutedSurface, in: Capsule())
    }

    private func filterButton(_ filter: GoalFilter, count: Int) -> some View {
        Button {
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) {
                selectedFilter = filter
            }
        } label: {
            Text("\(filter.title) \(count)")
                .font(.subheadline.weight(selectedFilter == filter ? .semibold : .regular))
                .foregroundStyle(selectedFilter == filter ? ZJTheme.ink : ZJTheme.secondaryInk)
                .frame(maxWidth: .infinity, minHeight: 36)
                .background(selectedFilter == filter ? ZJTheme.surface : Color.clear, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selectedFilter == filter ? .isSelected : [])
    }

    @ViewBuilder
    private var addGoalControls: some View {
        VStack(spacing: 8) {
            if isAddingGoal {
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
            } else {
                Button(action: beginCreatingGoal) {
                    Label("新建目标", systemImage: "plus")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: ZJTheme.controlHeight)
                }
                .buttonStyle(.plain)
                .foregroundStyle(ZJTheme.secondaryInk)
                .background(ZJTheme.mutedSurface, in: RoundedRectangle(cornerRadius: ZJTheme.cornerRadius, style: .continuous))
                .padding(.horizontal, ZJTheme.pagePadding)
            }
        }
        .padding(.top, 8)
        .padding(.bottom, 8)
        .background(ZJTheme.background)
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

private enum GoalFilter: CaseIterable {
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

private struct GoalRow: View {
    let goal: Goal

    private var progress: GoalProgress {
        GoalService.progress(for: goal)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                Image(systemName: goal.displayIconName)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(ZJTheme.accent)
                    .frame(width: 44, height: 44)
                    .background(ZJTheme.accentSoft, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                    .accessibilityLabel("目标图标，\(goal.icon.title)")

                VStack(alignment: .leading, spacing: 4) {
                    Text(goal.name)
                        .font(.headline)
                        .foregroundStyle(ZJTheme.ink)

                    Text(progress.total == 0 ? "从一个小任务开始" : "已完成 \(progress.completed) 件，共 \(progress.total) 件")
                        .font(.caption)
                        .foregroundStyle(ZJTheme.secondaryInk)
                }
            }

            HStack(spacing: 12) {
                Text("\(progress.percentage)%")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(ZJTheme.ink)

                ProgressView(value: progress.fraction)
                    .tint(ZJTheme.accent)

                Text("\(progress.completed) / \(progress.total)")
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(ZJTheme.secondaryInk)
            }
        }
        .padding(18)
        .zjCard()
    }
}
