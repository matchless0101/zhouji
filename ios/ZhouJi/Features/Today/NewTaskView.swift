import SwiftData
import SwiftUI

struct NewTaskView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @Query(
        filter: #Predicate<Goal> { $0.deletedAt == nil },
        sort: \Goal.createdAt
    )
    private var visibleGoals: [Goal]

    @State private var draftTitle = ""
    @State private var selectedGoal: Goal?
    @State private var presentedError: String?
    @FocusState private var isTitleFocused: Bool

    private var normalizedTitle: String {
        draftTitle.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        ZStack {
            ZJTheme.pageBackground.ignoresSafeArea()

            GeometryReader { proxy in
                let isCompact = proxy.size.height < 520
                ScrollView {
                    VStack(alignment: .leading, spacing: isCompact ? 14 : 20) {
                        pageHeader
                        titleCard
                        goalChoices
                    }
                    .padding(.horizontal, ZJTheme.pagePadding)
                    .padding(.top, isCompact ? 4 : 10)
                    .padding(.bottom, 16)
                }
                .scrollDismissesKeyboard(.interactively)
            }
        }
        .background(TaskNavigationBackground())
        .tint(ZJTheme.accent)
        .toolbar(.hidden, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            submitBar
        }
        .defaultFocus($isTitleFocused, true)
        .task {
            isTitleFocused = true
        }
        .alert(
            "任务没有添加",
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

    private var pageHeader: some View {
        ZStack {
            Text("记一件事")
                .font(.headline.weight(.bold))
                .foregroundStyle(ZJTheme.ink)
                .accessibilityAddTraits(.isHeader)
            HStack {
                Button(action: dismiss.callAsFunction) {
                    Image(systemName: "xmark")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(ZJTheme.ink)
                        .frame(width: 44, height: 44)
                        .background(ZJTheme.surface, in: Circle())
                        .compositingGroup()
                        .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 4)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("返回今天")
                Spacer()
            }
        }
    }

    private var titleCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("任务名称")
                .font(.caption.weight(.medium))
                .foregroundStyle(ZJTheme.secondaryInk)

            HStack(spacing: 6) {
                TextField("今天要做什么？", text: $draftTitle)
                    .textFieldStyle(.plain)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(ZJTheme.ink)
                    .focused($isTitleFocused)
                    .submitLabel(.done)
                    .onSubmit(createTask)

                if !draftTitle.isEmpty {
                    Button {
                        draftTitle = ""
                        isTitleFocused = true
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(ZJTheme.secondaryInk)
                            .frame(width: 30, height: 30)
                            .background(ZJTheme.mutedSurface, in: Circle())
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("清空任务名称")
                }
            }
            .frame(minHeight: 44)

            Capsule()
                .fill(ZJTheme.ink)
                .frame(height: 1.5)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 18)
        .padding(.top, 16)
        .padding(.bottom, 18)
        .zjCard()
    }

    /// Goals are picked from a row of chips; "不选" keeps the task without a goal.
    private var goalChoices: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("所属目标 · 可选")
                .font(.caption.weight(.medium))
                .foregroundStyle(ZJTheme.secondaryInk)
                .padding(.horizontal, 4)
                .accessibilityHidden(true)

            ChipFlowLayout(spacing: 8) {
                goalChip(title: "不选", isSelected: selectedGoal == nil, identifier: "today.goal.none") {
                    selectedGoal = nil
                }
                ForEach(visibleGoals) { goal in
                    goalChip(title: goal.name, isSelected: selectedGoal?.id == goal.id, identifier: "today.goal.option") {
                        selectedGoal = goal
                    }
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("所属目标")
            .accessibilityIdentifier("today.goalPicker")
        }
    }

    private func goalChip(title: String, isSelected: Bool, identifier: String,
                          action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .foregroundStyle(isSelected ? ZJTheme.onAccent : ZJTheme.ink)
                .padding(.horizontal, 16)
                .frame(minHeight: 44)
                .background(isSelected ? ZJTheme.accent : ZJTheme.surface, in: Capsule())
                .compositingGroup()
                .shadow(color: .black.opacity(isSelected ? 0.18 : 0.05), radius: isSelected ? 9 : 6, x: 0, y: 4)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var submitBar: some View {
        Button(action: createTask) {
            Label("添加任务", systemImage: "plus")
        }
        .buttonStyle(ZJPrimaryButtonStyle())
        .disabled(normalizedTitle.isEmpty)
        .accessibilityLabel("添加")
        .padding(.horizontal, ZJTheme.pagePadding)
        .padding(.top, 8)
        .padding(.bottom, 10)
        .background(ZJTheme.background)
    }

    private func createTask() {
        guard !normalizedTitle.isEmpty else { return }
        do {
            _ = try TaskService.create(title: draftTitle, goal: selectedGoal, in: modelContext)
            dismiss()
        } catch {
            presentedError = error.localizedDescription
        }
    }
}

#Preview {
    NavigationStack {
        NewTaskView()
    }
    .modelContainer(for: [Goal.self, TodoTask.self, TimingSession.self], inMemory: true)
}

/// Wraps chips onto as many rows as they need; a chip never grows wider than the row.
private struct ChipFlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        let rows = arrange(subviews, width: width)
        let height = rows.last.map { $0.y + $0.height } ?? 0
        return CGSize(width: proposal.width ?? rows.map(\.width).max() ?? 0, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for row in arrange(subviews, width: bounds.width) {
            for item in row.items {
                subviews[item.index].place(at: CGPoint(x: bounds.minX + item.x, y: bounds.minY + row.y),
                                           proposal: ProposedViewSize(item.size))
            }
        }
    }

    private struct Row {
        var y: CGFloat
        var height: CGFloat = 0
        var width: CGFloat = 0
        var items: [(index: Int, x: CGFloat, size: CGSize)] = []
    }

    private func arrange(_ subviews: Subviews, width: CGFloat) -> [Row] {
        var rows = [Row(y: 0)]
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(ProposedViewSize(width: width, height: nil))
            if !rows[rows.count - 1].items.isEmpty, rows[rows.count - 1].width + spacing + size.width > width {
                let last = rows[rows.count - 1]
                rows.append(Row(y: last.y + last.height + spacing))
            }
            var row = rows[rows.count - 1]
            let x = row.items.isEmpty ? 0 : row.width + spacing
            row.items.append((index, x, size))
            row.width = x + size.width
            row.height = max(row.height, size.height)
            rows[rows.count - 1] = row
        }
        return rows
    }
}

// SwiftUI's native navigation/tab containers can expose their default background
// before the hidden tab bar finishes its transition. Keep that surface on the page color.
struct TaskNavigationBackground: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> PageBackgroundController { PageBackgroundController() }
    func updateUIViewController(_ controller: PageBackgroundController, context: Context) {}

    final class PageBackgroundController: UIViewController {
        override func loadView() {
            view = UIView()
            view.backgroundColor = .clear
            view.isUserInteractionEnabled = false
        }

        override func didMove(toParent parent: UIViewController?) {
            super.didMove(toParent: parent)
            applyBackground()
        }

        private func applyBackground() {
            let paperColor = UIColor(ZJTheme.background)
            var ancestor = parent
            while let controller = ancestor {
                if let tab = controller as? UITabBarController {
                    tab.view.backgroundColor = paperColor
                    tab.selectedViewController?.view.backgroundColor = paperColor
                    break
                }
                ancestor = controller.parent
            }
        }
    }
}
