import SwiftData
import SwiftUI
import UIKit

struct ProfileView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Query private var tasks: [TodoTask]
    @Query private var sessions: [TimingSession]
    @State private var presentedPanel: ProfilePanel?

    private var completedCount: Int { tasks.count { $0.completedAt != nil } }

    private var completionRate: Int {
        let visibleTasks = tasks.filter { $0.deletedAt == nil }
        guard !visibleTasks.isEmpty else { return 0 }
        return Int((Double(visibleTasks.count { $0.isCompleted }) / Double(visibleTasks.count) * 100).rounded())
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    header
                    menuCard
                    if !dynamicTypeSize.isAccessibilitySize { postcard }
                }
                .padding(.horizontal, ZJTheme.pagePadding + 6)
                .padding(.top, 30)
                .padding(.bottom, 28)
            }
            .background(ZJTheme.pageBackground.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .overlay(alignment: .topTrailing) {
                Button { presentedPanel = .preferences } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 25, weight: .regular))
                        .foregroundStyle(ZJTheme.ink)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("偏好设置")
                .accessibilityIdentifier("profile.settings")
                .padding(.top, 12)
                .padding(.trailing, ZJTheme.pagePadding + 6)
            }
            .sheet(item: $presentedPanel) { panel in
                switch panel {
                case .preferences:
                    ProfilePreferencesView()
                case .overview:
                    overview
                case .calendar:
                    CalendarView()
                        .safeAreaInset(edge: .top, spacing: 0) {
                            HStack {
                                Text("日历回顾").font(.headline).foregroundStyle(ZJTheme.ink)
                                Spacer()
                                closePanelButton
                            }
                            .padding(.horizontal, ZJTheme.pagePadding)
                            .padding(.vertical, 10)
                            .background(ZJTheme.surface)
                        }
                }
            }
        }
    }

    private var header: some View {
        VStack(spacing: 9) {
            if !dynamicTypeSize.isAccessibilitySize {
                ZJIllustration(name: "LiuliHeart", height: 175)
                    .background {
                        Circle().fill(ZJTheme.accentSoft.opacity(0.55)).frame(width: 166, height: 166)
                    }
            }
            Text("一粥又一周")
                .accessibilityAddTraits(.isHeader)
                .font(ZJTheme.handwriting(dynamicTypeSize.isAccessibilitySize ? 28 : 32, relativeTo: .title2))
                .foregroundStyle(ZJTheme.ink)
            if !dynamicTypeSize.isAccessibilitySize {
                Text("把平凡的日子，\n过成喜欢的样子。")
                    .font(ZJTheme.handwriting(19, relativeTo: .body))
                    .multilineTextAlignment(.center)
                    .lineSpacing(5)
                    .foregroundStyle(ZJTheme.secondaryInk)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, dynamicTypeSize.isAccessibilitySize ? 42 : 22)
    }

    private var menuCard: some View {
        VStack(spacing: 0) {
            panelButton(.overview, title: "我的概况", symbol: "star.fill", tint: Color(red: 0.88, green: 0.65, blue: 0.29), identifier: "profile.overview")
            menuDivider
            panelButton(.calendar, title: "日历回顾", symbol: "clock", tint: ZJTheme.secondaryInk, identifier: "profile.review")
            menuDivider
            panelButton(.preferences, title: "偏好设置", symbol: "leaf.fill", tint: ZJTheme.success, identifier: "profile.preferences")
        }
        .zjCard()
    }

    private var menuDivider: some View {
        Divider().overlay(ZJTheme.divider.opacity(0.7)).padding(.horizontal, 18)
    }

    private func panelButton(_ panel: ProfilePanel, title: String, symbol: String, tint: Color, identifier: String) -> some View {
        Button { presentedPanel = panel } label: {
            HStack(spacing: 16) {
                Image(systemName: symbol).font(.system(size: 26, weight: .regular))
                    .foregroundStyle(tint).frame(width: 32).accessibilityHidden(true)
                Text(title).font(ZJTheme.handwriting(20, relativeTo: .body)).foregroundStyle(ZJTheme.ink)
                Spacer(minLength: 8)
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(ZJTheme.ink).accessibilityHidden(true)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
            .frame(minHeight: 62)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
    }

    private var postcard: some View {
        HStack(spacing: 0) {
            Image("LiuliCalendar")
                .resizable()
                .scaledToFill()
                .frame(width: 205, height: 132)
                .clipped()
                .background(ZJTheme.accentSoft)
                .padding(8)
                .background(ZJTheme.surface)
                .overlay { Rectangle().strokeBorder(ZJTheme.divider, lineWidth: 1) }
                .rotationEffect(.degrees(-8))
            Text("MORE\nGOOD\nDAYS.")
                .font(ZJTheme.handwriting(20, relativeTo: .body))
                .tracking(2)
                .lineSpacing(3)
                .foregroundStyle(ZJTheme.ink)
                .padding(12)
                .background(ZJTheme.surface)
                .rotationEffect(.degrees(7))
                .padding(.leading, -18)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 10)
        .padding(.bottom, 18)
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }

    private var closePanelButton: some View {
        Button { presentedPanel = nil } label: {
            Text("关闭")
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
            .foregroundStyle(ZJTheme.accent)
            .accessibilityIdentifier("profile.closePanel")
    }

    private var overview: some View {
        NavigationStack {
            TimelineView(.periodic(from: .now, by: sessions.contains { $0.state == .running } ? 1 : 60)) { context in
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        Text("每一步，都算数。")
                            .font(ZJTheme.handwriting(30, relativeTo: .title))
                            .foregroundStyle(ZJTheme.ink)
                        metrics(StatisticsService.snapshot(tasks: tasks, sessions: sessions, now: context.date))
                    }
                    .padding(ZJTheme.pagePadding)
                }
            }
            .background(ZJTheme.pageBackground.ignoresSafeArea())
            .navigationTitle("我的概况")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { closePanelButton } }
        }
    }

    private func metrics(_ statistics: StatisticsSnapshot) -> some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: 10))
            : AnyLayout(HStackLayout(alignment: .top, spacing: 10))
        return layout {
            metricCards(statistics)
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
            tint: ZJTheme.success,
            identifier: "profile.completionRate"
        )
    }

}

private enum ProfilePanel: String, Identifiable {
    case overview, calendar, preferences
    var id: String { rawValue }
}

private struct ProfilePreferencesView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AccountStore.self) private var account
    @Environment(LocalLibraryStore.self) private var libraries
    @Query private var tasks: [TodoTask]
    @AppStorage("appAppearance") private var appearanceRawValue = AppAppearance.system.rawValue
    @State private var isAboutPresented = false
    @State private var isProfileEditorPresented = false

    private var appearance: AppAppearance { AppAppearance(rawValue: appearanceRawValue) ?? .system }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    settingsCard
                    identityCard
                    AccountControls()
                    LocalLibraryCard()
                    BackupSettingsCard()
                    SyncSettingsCard()
                    AccountSessionActions()
                }
                .padding(.horizontal, ZJTheme.pagePadding)
                .padding(.top, 16)
                .padding(.bottom, 28)
            }
            .background(ZJTheme.pageBackground.ignoresSafeArea())
            .navigationTitle("偏好设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("关闭", action: dismiss.callAsFunction)
                        .accessibilityIdentifier("profile.closePanel")
                }
            }
            .sheet(isPresented: $isAboutPresented) { AboutZhouJiView() }
            .sheet(isPresented: $isProfileEditorPresented) {
                if let profile = account.account { ProfileEditor(profile: profile) }
            }
        }
        .tint(ZJTheme.accent)
    }

    @ViewBuilder private var identityCard: some View {
        if let profile = account.account {
            Button {
                isProfileEditorPresented = true
            } label: {
                HStack(spacing: 16) {
                    ProfileAvatarView(avatar: ProfileAvatar(rawValue: profile.avatar ?? "") ?? .sunrise)
                    VStack(alignment: .leading, spacing: 7) {
                        Text(profile.displayName)
                            .font(.title3.weight(.bold))
                            .foregroundStyle(ZJTheme.ink)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                            .accessibilityIdentifier("profile.displayName")
                        Label(profile.providerName, systemImage: profile.providerIcon)
                            .font(.caption)
                            .foregroundStyle(ZJTheme.secondaryInk)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(ZJTheme.secondaryInk)
                }
                .padding(16)
                .zjCard()
            }
            .buttonStyle(.plain)
            .disabled(account.isBusy)
            .accessibilityLabel("\(profile.displayName)，编辑个人资料")
            .accessibilityIdentifier("profile.edit")
        } else {
            guestIdentityCard
        }
    }

    private var guestIdentityCard: some View {
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
                Text(libraries.current.scope == LibraryScope.guest ? "游客模式" : "账户记录 · 离线")
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

struct ProfileSettingRow: View {
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
