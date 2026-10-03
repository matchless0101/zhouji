import SwiftData
import SwiftUI
import UIKit

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
    @State private var backgroundHeight: CGFloat = 0
    @State private var isKeyboardVisible = false
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
                        ForEach(filteredGoals) { goal in
                            Button {
                                navigationPath.append(.tasks(goal))
                            } label: {
                                GoalRow(goal: goal)
                            }
                            .buttonStyle(.plain)
                            .listRowInsets(EdgeInsets(top: 6, leading: ZJTheme.pagePadding + 6, bottom: 6, trailing: ZJTheme.pagePadding + 6))
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
                    Color.clear.frame(height: 255)
                        .accessibilityHidden(true)
                        .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
                .listStyle(.plain)
                .contentMargins(.top, 0, for: .scrollContent)
                .contentMargins(.bottom, 16, for: .scrollContent)
                .scrollContentBackground(.hidden)
                .clipped()
            }
            .toolbar(.hidden, for: .navigationBar)
            .safeAreaInset(edge: .top, spacing: 0) {
                pageHeader
                    .padding(.horizontal, ZJTheme.pagePadding + 6)
                    .padding(.top, 20)
                    .padding(.bottom, 14)
                    .background(ZJTheme.pageBackground)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if isAddingGoal { addGoalControls }
            }
            .background(alignment: .top) {
                ZStack(alignment: .bottom) {
                    ZJTheme.pageBackground.ignoresSafeArea()
                    GeometryReader { proxy in
                        Image(decorative: "LiuliGoalsReference")
                            .resizable()
                            .scaledToFit()
                            .frame(width: proxy.size.width * 1.4, height: proxy.size.width * 1.4 / 1.5)
                            .frame(width: proxy.size.width, height: 255, alignment: .bottom)
                            .clipped()
                    }
                    .frame(height: 255)
                    .allowsHitTesting(false)
                }
                .frame(height: backgroundHeight, alignment: .bottom)
            }
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                // Preserve the resting canvas while the input bar and keyboard reduce the viewport.
                guard !isAddingGoal, !isKeyboardVisible else { return }
                backgroundHeight = height
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
                isKeyboardVisible = true
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardDidHideNotification)) { _ in
                isKeyboardVisible = false
            }
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

    private var pageHeader: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center) {
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
                    Text("我的目标")
                        .font(ZJTheme.handwriting(34, relativeTo: .largeTitle).weight(.bold))
                        .foregroundStyle(ZJTheme.ink)
                        .frame(minHeight: 44, alignment: .leading)
                }
                .accessibilityLabel("我的目标，筛选目标")
                .accessibilityIdentifier("目标筛选")
                .accessibilityValue(selectedFilter.title)
                .accessibilityHint("轻点标题选择全部、进行中或已完成目标")
                Spacer(minLength: 8)
                if !isAddingGoal {
                    Button(action: beginCreatingGoal) {
                        Image(systemName: "plus")
                    }
                    .buttonStyle(ZJAddButtonStyle(diameter: 36))
                    .frame(width: 44, height: 44)
                    .accessibilityLabel("新建目标")
                }
            }
            HStack(alignment: .bottom) {
                if !dynamicTypeSize.isAccessibilitySize {
                    Text("慢一点，\n但一直向前。")
                        .font(ZJTheme.handwriting(19, relativeTo: .body))
                        .lineSpacing(4)
                        .foregroundStyle(ZJTheme.secondaryInk)
                }
                Spacer(minLength: 8)
            }
        }
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
            }
        }
        .padding(.top, 8)
        .padding(.bottom, isAddingGoal ? 8 : 16)
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

private struct GoalRow: View {
    let goal: Goal
    private var progress: GoalProgress { GoalService.progress(for: goal) }

    var body: some View {
        HStack(spacing: 16) {
            GoalListIcon(iconName: goal.displayIconName)
            Text(goal.name)
                .font(ZJTheme.handwriting(20, relativeTo: .body))
                .foregroundStyle(ZJTheme.ink)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(ZJTheme.ink)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .frame(minHeight: 78)
        .background(ZJTheme.surface, in: RoundedRectangle(cornerRadius: ZJTheme.cornerRadius))
        .accessibilityElement(children: .combine)
        .accessibilityValue("完成 \(progress.completed) 个，共 \(progress.total) 个任务，进度百分之 \(progress.percentage)")
    }
}

private struct GoalListIcon: View {
    let iconName: String

    var body: some View {
        Group {
            if iconName == "book.closed" {
                Canvas { context, size in
                    let cover = CGRect(x: 7, y: 4, width: 30, height: 36)
                    context.fill(Path(roundedRect: cover, cornerRadius: 3), with: .color(ZJTheme.success))
                    var spine = Path()
                    spine.move(to: CGPoint(x: 12, y: 6))
                    spine.addLine(to: CGPoint(x: 12, y: 34))
                    spine.addLine(to: CGPoint(x: 35, y: 34))
                    context.stroke(spine, with: .color(ZJTheme.onAccent), style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
                    for index in 0..<42 {
                        let x = CGFloat((index * 17 + 3) % 27) + 8
                        let y = CGFloat((index * 11 + 9) % 33) + 5
                        context.fill(Path(ellipseIn: CGRect(x: x, y: y, width: 0.7, height: 0.7)),
                                     with: .color(ZJTheme.onAccent.opacity(0.35)))
                    }
                }
            } else if iconName == "heart" {
                Image(systemName: "heart.fill")
                    .font(.system(size: 34, weight: .regular))
                    .foregroundStyle(ZJTheme.accent)
            } else {
                ZJIcon(systemName: iconName, size: 52)
            }
        }
        .frame(width: 44, height: 44)
        .accessibilityHidden(true)
    }
}
