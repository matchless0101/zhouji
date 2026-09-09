import SwiftData
import SwiftUI
import UIKit

struct GoalsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @Query(
        filter: #Predicate<Goal> { $0.deletedAt == nil },
        sort: \Goal.createdAt
    )
    private var visibleGoals: [Goal]

    @State private var isAddingGoal = false
    @State private var selectedGoal: Goal?
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
        NavigationStack {
            ZStack {
                ZJTheme.pageBackground.ignoresSafeArea()

                List {
                    pageHeader
                        .listRowInsets(EdgeInsets(top: ZJTheme.pageTopSpacing, leading: ZJTheme.pagePadding + 6, bottom: 12, trailing: ZJTheme.pagePadding))
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)

                    filterBar
                        .listRowInsets(EdgeInsets(top: 0, leading: ZJTheme.pagePadding, bottom: 12, trailing: ZJTheme.pagePadding))
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)

                    if filteredGoals.isEmpty {
                        ZJEmptyState(
                            title: visibleGoals.isEmpty ? "想持续推进什么？" : "这里还没有目标",
                            message: visibleGoals.isEmpty ? "先写下一个目标，再用每天的小任务慢慢靠近。" : "换个分类看看，或继续推进现有目标。",
                            systemImage: visibleGoals.isEmpty ? "scope" : "line.3.horizontal.decrease"
                        )
                        .padding(18)
                        .zjCard()
                        .listRowInsets(EdgeInsets(top: 8, leading: ZJTheme.pagePadding, bottom: 8, trailing: ZJTheme.pagePadding))
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                    } else {
                        ForEach(filteredGoals) { goal in
                            Button {
                                selectedGoal = goal
                            } label: {
                                GoalRow(goal: goal)
                            }
                            .buttonStyle(.plain)
                            .listRowInsets(EdgeInsets(top: 8, leading: ZJTheme.pagePadding, bottom: 8, trailing: ZJTheme.pagePadding))
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
                    if !isAddingGoal {
                        addGoalControls
                            .listRowInsets(EdgeInsets(top: 10, leading: 0, bottom: 24, trailing: 0))
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                    }
                }
                .listStyle(.plain)
                .contentMargins(.top, 0, for: .scrollContent)
                .scrollContentBackground(.hidden)
                .background(Color.clear)
            }
            .toolbar(.hidden, for: .navigationBar)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if isAddingGoal { addGoalControls }
            }
            .navigationDestination(item: $selectedGoal) { goal in
                GoalDetailView(goal: goal)
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
        Text("目标")
            .font(.largeTitle.weight(.bold))
            .foregroundStyle(ZJTheme.ink)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var filterBar: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: 4))
            : AnyLayout(HStackLayout(spacing: 4))

        return layout {
            filterButton(.all, count: visibleGoals.count)
            filterButton(.inProgress, count: inProgressGoals.count)
            filterButton(.completed, count: completedGoals.count)
        }
        .padding(2)
        .background(
            ZJTheme.mutedSurface.opacity(0.82),
            in: RoundedRectangle(cornerRadius: ZJTheme.cornerRadius, style: .continuous)
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("目标筛选")
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
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(selectedFilter == filter ? ZJTheme.surface : Color.clear, in: Capsule())
                .shadow(
                    color: selectedFilter == filter ? ZJTheme.accent.opacity(0.08) : .clear,
                    radius: 8,
                    x: 0,
                    y: 3
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(filter.title)
        .accessibilityValue("\(count) 个目标")
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
                    Label {
                        Text("新建目标")
                            .foregroundStyle(ZJTheme.secondaryInk)
                    } icon: {
                        Image(systemName: "plus")
                            .foregroundStyle(ZJTheme.secondaryInk)
                    }
                    .font(.body)
                    .frame(maxWidth: .infinity, minHeight: 56)
                }
                .buttonStyle(.zjSecondary)
                .padding(.horizontal, ZJTheme.pagePadding)
            }
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
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let goal: Goal

    private var progress: GoalProgress {
        GoalService.progress(for: goal)
    }

    private var illustrationAssetName: String? {
        switch goal.icon {
        case .book, .study:
            "GoalWriting"
        case .work:
            "GoalCareer"
        case .digital:
            "GoalDigital"
        default:
            nil
        }
    }

    var body: some View {
        let goalColor = ZJTheme.goalAccent(for: goal.displayIconName)

        return VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 14) {
                ZJGoalIcon(iconName: goal.displayIconName, size: 60)

                VStack(alignment: .leading, spacing: 5) {
                    Text(goal.name)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(ZJTheme.ink)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(progress.total == 0 ? "从一个小任务开始" : "一步一步，靠近目标。")
                        .font(.subheadline)
                        .foregroundStyle(ZJTheme.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .layoutPriority(1)

                Image(systemName: "chevron.right")
                    .font(.body.weight(.medium))
                    .foregroundStyle(ZJTheme.secondaryInk)
                    .accessibilityHidden(true)
            }

            HStack(spacing: 16) {
                Text("\(progress.percentage)%")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(ZJTheme.ink)
                    .frame(minWidth: 60, alignment: .leading)

                ProgressView(value: progress.fraction)
                    .tint(ZJTheme.goalProgress(for: goal.displayIconName))
                    .scaleEffect(x: 1, y: 1.5)
                    .accessibilityLabel("目标进度")
                    .accessibilityValue("百分之 \(progress.percentage)")

                Text("\(progress.completed) / \(progress.total)")
                    .font(.subheadline)
                    .monospacedDigit()
                    .foregroundStyle(ZJTheme.secondaryInk)
            }
        }
        .padding(16)
        .background(alignment: .topTrailing) {
            if let illustrationAssetName, colorScheme == .light, !dynamicTypeSize.isAccessibilitySize,
               let illustration = UIImage(named: illustrationAssetName) {
                Image(uiImage: illustration)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 106, height: 106)
                    .opacity(0.34)
                    .blendMode(.multiply)
                    .compositingGroup()
                    .padding(.trailing, 8)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            } else {
                Image(systemName: goal.displayIconName)
                    .font(.system(size: 64, weight: .light))
                    .foregroundStyle(goalColor.opacity(0.06))
                    .rotationEffect(.degrees(-12))
                    .padding(20)
                    .accessibilityHidden(true)
            }
        }
        .zjCard()
    }
}
