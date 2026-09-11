import SwiftData
import SwiftUI
import UIKit

struct ProfileView: View {
    @Query private var tasks: [TodoTask]
    @Query private var sessions: [TimingSession]

    @AppStorage("appAppearance") private var appearanceRawValue = AppAppearance.system.rawValue
    @State private var isAboutPresented = false

    private var appearance: AppAppearance {
        AppAppearance(rawValue: appearanceRawValue) ?? .system
    }

    private var visibleTasks: [TodoTask] {
        tasks.filter { $0.deletedAt == nil }
    }

    private var completedCount: Int {
        tasks.count { $0.completedAt != nil }
    }

    private var completionRate: Int {
        guard !visibleTasks.isEmpty else { return 0 }
        let completed = visibleTasks.count { $0.isCompleted }
        return Int((Double(completed) / Double(visibleTasks.count) * 100).rounded())
    }

    var body: some View {
        NavigationStack {
            TimelineView(.periodic(from: .now, by: sessions.contains(where: { $0.state == .running }) ? 1 : 60)) { context in
                let statistics = StatisticsService.snapshot(
                    tasks: tasks,
                    sessions: sessions,
                    now: context.date
                )

                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        header
                        identityCard
                        metrics(statistics)
                        encouragementBanner
                        settingsCard
                    }
                    .padding(.horizontal, ZJTheme.pagePadding)
                    .padding(.top, 12)
                    .padding(.bottom, 44)
                }
            }
            .background(ZJTheme.pageBackground.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $isAboutPresented) {
                AboutZhouJiView()
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("我的")
                .font(.largeTitle.weight(.bold))
                .foregroundStyle(ZJTheme.ink)

            Text("持续积累，遇见更好的自己。")
                .font(.subheadline)
                .foregroundStyle(ZJTheme.secondaryInk)
        }
    }

    private var identityCard: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [ZJTheme.accentSoft, ZJTheme.mutedSurface],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                Image(systemName: "person.fill")
                    .font(.system(size: 32, weight: .medium))
                    .foregroundStyle(ZJTheme.accent)
            }
            .frame(width: 72, height: 72)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 5) {
                Text("游客模式")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(ZJTheme.ink)

                Text("数据仅保存在本机，尚未进行云同步。卸载 App 或更换设备时，数据可能丢失。")
                    .font(.subheadline)
                    .foregroundStyle(ZJTheme.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(16)
        .zjCard()
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("profile.guestNotice")
    }

    private func metrics(_ statistics: StatisticsSnapshot) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 10) {
                metricCards(statistics)
            }

            VStack(spacing: 10) {
                metricCards(statistics)
            }
        }
    }

    @ViewBuilder
    private func metricCards(_ statistics: StatisticsSnapshot) -> some View {
        ProfileMetricCard(
            title: "累计完成",
            value: "\(completedCount) 件",
            detail: "每一步都算数",
            systemImage: "checkmark.circle.fill",
            tint: ZJTheme.timerAccent,
            identifier: "profile.completed"
        )

        ProfileMetricCard(
            title: "本周专注",
            value: ElapsedTimeText.string(for: statistics.secondsThisWeek),
            detail: "来自真实计时",
            systemImage: "clock.fill",
            tint: ZJTheme.accent,
            identifier: "profile.weekFocus"
        )

        ProfileMetricCard(
            title: "任务完成率",
            value: "\(completionRate)%",
            detail: "当前任务进度",
            systemImage: "chart.bar.fill",
            tint: Color.green,
            identifier: "profile.completionRate"
        )
    }

    private var encouragementBanner: some View {
        HStack(spacing: 10) {
            Text("每一个小小的坚持，\n都在让你靠近理想的自己。")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(ZJTheme.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)

            if let illustration = UIImage(named: "TodayJourney") {
                Image(uiImage: illustration)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 112, height: 74)
                    .scaleEffect(1.12)
                    .blendMode(.multiply)
                    .compositingGroup()
                    .clipShape(.rect(cornerRadius: 16))
                    .accessibilityHidden(true)
            }
        }
        .padding(.leading, 18)
        .padding(.trailing, 8)
        .frame(minHeight: 96)
        .background(ZJTheme.accentSoft.opacity(0.78), in: RoundedRectangle(cornerRadius: ZJTheme.cornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: ZJTheme.cornerRadius, style: .continuous)
                .stroke(ZJTheme.accent.opacity(0.12), lineWidth: 0.6)
        }
        .accessibilityElement(children: .combine)
    }

    private var settingsCard: some View {
        VStack(spacing: 0) {
            Menu {
                ForEach(AppAppearance.allCases) { option in
                    Button {
                        appearanceRawValue = option.rawValue
                    } label: {
                        if appearance == option {
                            Label(option.title, systemImage: "checkmark")
                        } else {
                            Text(option.title)
                        }
                    }
                }
            } label: {
                ProfileSettingRow(
                    title: "外观",
                    detail: appearance.title,
                    systemImage: "moon",
                    showsChevron: true
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("外观")
            .accessibilityValue(appearance.title)

            settingDivider

            ProfileSettingRow(
                title: "数据与存储",
                detail: "本机存储 · \(tasks.count) 项任务",
                systemImage: "externaldrive",
                showsChevron: false
            )
            .accessibilityElement(children: .combine)

            settingDivider

            Button {
                isAboutPresented = true
            } label: {
                ProfileSettingRow(
                    title: "关于粥记",
                    detail: "版本 \(Self.appVersion)",
                    systemImage: "info.circle",
                    showsChevron: true
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("关于粥记")
            .accessibilityValue("版本 \(Self.appVersion)")
        }
        .zjCard()
    }

    private var settingDivider: some View {
        Divider()
            .overlay(ZJTheme.divider)
            .padding(.leading, 62)
    }

    private static var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }
}

private struct ProfileMetricCard: View {
    let title: String
    let value: String
    let detail: String
    let systemImage: String
    let tint: Color
    let identifier: String

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Image(systemName: systemImage)
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(tint)

            Text(title)
                .font(.caption)
                .foregroundStyle(ZJTheme.secondaryInk)
                .lineLimit(1)

            Text(value)
                .font(.title3.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(ZJTheme.ink)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
                .accessibilityIdentifier(identifier)

            Text(detail)
                .font(.caption2)
                .foregroundStyle(ZJTheme.secondaryInk)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, minHeight: 118, alignment: .topLeading)
        .padding(14)
        .zjCard()
    }
}

private struct ProfileSettingRow: View {
    let title: String
    let detail: String
    let systemImage: String
    let showsChevron: Bool

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: systemImage)
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(ZJTheme.accent)
                .frame(width: 34, height: 34)
                .background(ZJTheme.accentSoft, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                .accessibilityHidden(true)

            Text(title)
                .font(.body.weight(.semibold))
                .foregroundStyle(ZJTheme.ink)

            Spacer(minLength: 8)

            Text(detail)
                .font(.caption)
                .foregroundStyle(ZJTheme.secondaryInk)
                .lineLimit(1)

            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(ZJTheme.secondaryInk)
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 62)
        .contentShape(Rectangle())
    }
}

private struct AboutZhouJiView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                ZJTheme.pageBackground.ignoresSafeArea()

                VStack(spacing: 18) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 56, weight: .medium))
                        .foregroundStyle(ZJTheme.accent)

                    Text("粥记")
                        .font(.largeTitle.weight(.bold))
                        .foregroundStyle(ZJTheme.ink)

                    Text("打开即做，记录真实投入。\n把重要的事，一件一件完成。")
                        .font(.body)
                        .foregroundStyle(ZJTheme.secondaryInk)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(28)
            }
            .navigationTitle("关于粥记")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
        }
        .presentationBackground(ZJTheme.background)
    }
}

#Preview {
    ProfileView()
        .modelContainer(for: [Goal.self, TodoTask.self, TimingSession.self], inMemory: true)
}
