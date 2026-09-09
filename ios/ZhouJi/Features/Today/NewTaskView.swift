import SwiftData
import SwiftUI
import UIKit

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

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    pageHeader
                    taskForm
                }
                .padding(.horizontal, ZJTheme.pagePadding)
                .padding(.top, 12)
                .padding(.bottom, 28)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .toolbar(.hidden, for: .navigationBar)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            submitBar
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
        VStack(alignment: .leading, spacing: 18) {
            Button(action: dismiss.callAsFunction) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(ZJTheme.secondaryInk)
                    .frame(width: 44, height: 44)
                    .background(ZJTheme.surface, in: Circle())
                    .overlay {
                        Circle().stroke(ZJTheme.divider.opacity(0.7), lineWidth: 0.5)
                    }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("返回今天")

            ViewThatFits(in: .horizontal) {
                HStack(alignment: .bottom, spacing: 14) {
                    headerCopy
                    Spacer(minLength: 8)
                    writingIllustration
                }

                headerCopy
            }
        }
    }

    private var headerCopy: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("新建任务")
                .font(.largeTitle.weight(.bold))
                .foregroundStyle(ZJTheme.ink)

            Text("把想做的事，变成可以完成的行动。")
                .font(.subheadline)
                .foregroundStyle(ZJTheme.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var writingIllustration: some View {
        if let illustration = UIImage(named: "GoalWriting") {
            Image(uiImage: illustration)
                .resizable()
                .scaledToFill()
                .frame(width: 112, height: 92)
                .scaleEffect(1.12)
                .blendMode(.multiply)
                .compositingGroup()
                .clipShape(.rect(cornerRadius: 18))
                .accessibilityHidden(true)
        }
    }

    private var taskForm: some View {
        VStack(alignment: .leading, spacing: 0) {
            formLabel("任务名称")

            HStack(spacing: 10) {
                TextField("今天要做什么？", text: $draftTitle)
                    .textFieldStyle(.plain)
                    .font(.body.weight(.medium))
                    .foregroundStyle(ZJTheme.ink)
                    .focused($isTitleFocused)
                    .submitLabel(.done)
                    .onSubmit(createTask)

                if !draftTitle.isEmpty {
                    Button {
                        draftTitle = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(ZJTheme.secondaryInk.opacity(0.45))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("清空任务名称")
                }
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 52)
            .background(ZJTheme.mutedSurface.opacity(0.76), in: RoundedRectangle(cornerRadius: ZJTheme.compactCornerRadius))

            formDivider

            formLabel("关联目标")
            goalPicker

            formDivider

            Label("任务保持简单：只记录名称和归属目标。", systemImage: "sparkles")
                .font(.footnote)
                .foregroundStyle(ZJTheme.secondaryInk)
                .padding(.vertical, 4)
                .accessibilityElement(children: .combine)
        }
        .padding(16)
        .zjCard()
    }

    private func formLabel(_ title: String) -> some View {
        Text(title)
            .font(.headline)
            .foregroundStyle(ZJTheme.ink)
            .padding(.bottom, 10)
    }

    private var formDivider: some View {
        Divider()
            .overlay(ZJTheme.divider)
            .padding(.vertical, 16)
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
                if let selectedGoal {
                    ZJGoalIcon(iconName: selectedGoal.displayIconName, size: 48)
                } else {
                    ZJGoalIcon(iconName: "target", size: 48)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(selectedGoal?.name ?? "不关联目标")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(ZJTheme.ink)
                        .lineLimit(1)

                    Text(selectedGoal == nil ? "稍后也可以再决定" : "任务会计入这个目标的进度")
                        .font(.caption)
                        .foregroundStyle(ZJTheme.secondaryInk)
                        .lineLimit(2)
                }

                Spacer(minLength: 8)

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(ZJTheme.secondaryInk)
                    .accessibilityHidden(true)
            }
            .padding(12)
            .background(ZJTheme.mutedSurface.opacity(0.66), in: RoundedRectangle(cornerRadius: ZJTheme.compactCornerRadius))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("today.goalPicker")
        .accessibilityLabel("归属目标")
        .accessibilityValue(selectedGoal?.name ?? "无目标")
        .accessibilityHint("选择这个任务所属的目标")
    }

    private var submitBar: some View {
        Button(action: createTask) {
            Text("添加任务")
                .font(.headline)
                .foregroundStyle(ZJTheme.onAccent)
                .frame(maxWidth: .infinity, minHeight: 54)
                .background(
                    normalizedTitle.isEmpty ? ZJTheme.secondaryInk.opacity(0.35) : ZJTheme.accent,
                    in: RoundedRectangle(cornerRadius: ZJTheme.cornerRadius, style: .continuous)
                )
                .shadow(color: normalizedTitle.isEmpty ? .clear : ZJTheme.accent.opacity(0.22), radius: 16, x: 0, y: 7)
        }
        .buttonStyle(.plain)
        .disabled(normalizedTitle.isEmpty)
        .accessibilityLabel("添加")
        .padding(.horizontal, ZJTheme.pagePadding)
        .padding(.vertical, 10)
        .background(ZJTheme.background.opacity(0.96))
    }

    private func createTask() {
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
