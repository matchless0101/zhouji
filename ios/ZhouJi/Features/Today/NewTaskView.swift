import SwiftData
import SwiftUI

struct NewTaskView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

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
                    VStack(alignment: .leading, spacing: isCompact ? 12 : 20) {
                        pageHeader(isCompact: isCompact, width: proxy.size.width - ZJTheme.pagePadding * 2)
                        taskForm(isCompact: isCompact)
                        formHint
                    }
                    .padding(.horizontal, ZJTheme.pagePadding)
                    .padding(.top, isCompact ? 4 : 10)
                    .padding(.bottom, 16)
                }
                .scrollDismissesKeyboard(.interactively)
            }
        }
        .tint(ZJTheme.accent)
        .toolbar(.hidden, for: .navigationBar)
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

    private func pageHeader(isCompact: Bool, width: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: isCompact ? 6 : 12) {
            Button(action: dismiss.callAsFunction) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(ZJTheme.ink)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("返回今天")

            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: isCompact ? 8 : 12) {
                    Text("新建任务")
                        .font(ZJTheme.handwriting(isCompact ? 34 : 38, relativeTo: .largeTitle).weight(.bold))
                        .foregroundStyle(ZJTheme.ink)
                        .accessibilityAddTraits(.isHeader)

                    Text("把想做的事，\n变成可以完成的行动。")
                        .font(ZJTheme.handwriting(isCompact ? 15 : 17, relativeTo: .subheadline))
                        .lineSpacing(3)
                        .foregroundStyle(ZJTheme.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if dynamicTypeSize <= .large {
                    Image(decorative: "LiuliWriting")
                        .resizable()
                        .scaledToFit()
                        .frame(width: min(isCompact ? 132 : 180, width * 0.43))
                        .padding(.top, isCompact ? 6 : 12)
                        .allowsHitTesting(false)
                }
            }
        }
    }

    private func taskForm(isCompact: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            formLabel("任务名称")

            HStack(spacing: 0) {
                TextField("今天要做什么？", text: $draftTitle)
                    .textFieldStyle(.plain)
                    .font(.body)
                    .foregroundStyle(ZJTheme.ink)
                    .focused($isTitleFocused)
                    .submitLabel(.done)
                    .onSubmit(createTask)

                if !draftTitle.isEmpty {
                    Button {
                        draftTitle = ""
                        isTitleFocused = true
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 18))
                            .foregroundStyle(ZJTheme.secondaryInk.opacity(0.45))
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("清空任务名称")
                }
            }
            .padding(.leading, 14)
            .padding(.trailing, draftTitle.isEmpty ? 14 : 4)
            .frame(minHeight: 52)
            .background {
                inputSurface
            }

            Divider()
                .overlay(ZJTheme.divider.opacity(0.8))
                .padding(.vertical, isCompact ? 8 : 20)

            formLabel("关联目标")
            goalPicker
        }
        .padding(isCompact ? 12 : 16)
        .background(ZJTheme.surface, in: RoundedRectangle(cornerRadius: ZJTheme.cornerRadius))
        .overlay {
            RoundedRectangle(cornerRadius: ZJTheme.cornerRadius)
                .stroke(ZJTheme.divider.opacity(0.75), lineWidth: 0.8)
        }
    }

    private var inputSurface: some View {
        RoundedRectangle(cornerRadius: ZJTheme.compactCornerRadius)
            .fill(ZJTheme.background.opacity(0.45))
            .overlay {
                RoundedRectangle(cornerRadius: ZJTheme.compactCornerRadius)
                    .stroke(ZJTheme.divider.opacity(0.85), lineWidth: 0.8)
            }
    }

    private func formLabel(_ title: String) -> some View {
        Text(title)
            .font(ZJTheme.handwriting(18, relativeTo: .headline).weight(.bold))
            .foregroundStyle(ZJTheme.ink)
            .padding(.bottom, 8)
    }

    private var goalPicker: some View {
        Menu {
            Button {
                selectedGoal = nil
            } label: {
                if selectedGoal == nil {
                    Label("无目标", systemImage: "checkmark")
                } else {
                    Text("无目标")
                }
            }

            ForEach(visibleGoals) { goal in
                Button {
                    selectedGoal = goal
                } label: {
                    if selectedGoal?.id == goal.id {
                        Label(goal.name, systemImage: "checkmark")
                    } else {
                        Text(goal.name)
                    }
                }
            }
        } label: {
            HStack(spacing: 12) {
                ZJGoalIcon(iconName: selectedGoal?.displayIconName ?? "target", size: 36)

                VStack(alignment: .leading, spacing: 3) {
                    Text(selectedGoal?.name ?? "不关联目标")
                        .font(ZJTheme.handwriting(17, relativeTo: .body).weight(.bold))
                        .foregroundStyle(ZJTheme.ink)
                        .lineLimit(1)

                    Text(selectedGoal == nil ? "稍后也可以再决定" : "任务会计入这个目标的进度")
                        .font(ZJTheme.handwriting(13, relativeTo: .caption))
                        .foregroundStyle(ZJTheme.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 8)

                Image(systemName: "chevron.right")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(ZJTheme.secondaryInk)
                    .accessibilityHidden(true)
            }
            .padding(12)
            .frame(minHeight: 64)
            .background {
                inputSurface
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("today.goalPicker")
        .accessibilityLabel("归属目标")
        .accessibilityValue(selectedGoal?.name ?? "无目标")
        .accessibilityHint("选择这个任务所属的目标")
    }

    private var formHint: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "sparkle")
                .font(.system(size: 16))
                .accessibilityHidden(true)

            Text("任务保持简单：只记录名称和归属目标。")
                .font(ZJTheme.handwriting(14, relativeTo: .footnote))
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(ZJTheme.secondaryInk)
        .accessibilityElement(children: .combine)
    }

    private var submitBar: some View {
        Button(action: createTask) {
            Text("添加任务")
                .font(ZJTheme.handwriting(23, relativeTo: .headline))
                .foregroundStyle(ZJTheme.onAccent)
                .frame(maxWidth: .infinity, minHeight: 54)
                .padding(.vertical, 2)
                .background {
                    RoundedRectangle(cornerRadius: ZJTheme.cornerRadius)
                        .fill(normalizedTitle.isEmpty ? ZJTheme.secondaryInk.opacity(0.35) : ZJTheme.accent)
                        .overlay {
                            if !normalizedTitle.isEmpty {
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
