import SwiftData
import SwiftUI
import UIKit

struct ProfileView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(AccountStore.self) private var account
    @Environment(LocalLibraryStore.self) private var libraries
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
                VStack(alignment: .leading, spacing: 22) {
                    header
                    if !dynamicTypeSize.isAccessibilitySize { recordCard }
                    menu
                }
                .padding(.horizontal, ZJTheme.pagePadding + 2)
                .padding(.top, 30)
                .padding(.bottom, 28)
            }
            .background(ZJTheme.pageBackground.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .overlay(alignment: .topTrailing) {
                Button { presentedPanel = .preferences } label: {
                    ZJIcon(systemName: "gearshape", size: 40)
                        .frame(width: 44, height: 44)
                        .background {
                            Circle().fill(ZJTheme.surface).shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 4)
                        }
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
                case .editProfile:
                    if let profile = account.account { ProfileEditor(profile: profile) }
                }
            }
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            if let profile = account.account {
                let avatar = ProfileAvatar(rawValue: profile.avatar ?? "") ?? .liuli
                Button { presentedPanel = .editProfile } label: {
                    HStack(spacing: 14) {
                        ProfileAvatarView(avatar: avatar, size: 60)
                        VStack(alignment: .leading, spacing: 3) {
                            Label(profile.providerName, systemImage: profile.providerIcon)
                                .font(.caption)
                                .foregroundStyle(ZJTheme.secondaryInk)
                            Text(profile.displayName)
                                .font(.title2.weight(.bold))
                                .foregroundStyle(ZJTheme.ink)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(account.isBusy)
                .accessibilityLabel("\(profile.displayName)，编辑个人资料")
                .accessibilityValue("头像：\(avatar.title)")
                .accessibilityIdentifier("profile.identity")
            } else {
                ProfileAvatarView(avatar: .liuli, size: 60)
                VStack(alignment: .leading, spacing: 3) {
                    Text("你好，")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(ZJTheme.secondaryInk)
                    Text(libraries.current.scope == LibraryScope.guest ? "游客模式" : "账户记录 · 离线")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(ZJTheme.ink)
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityIdentifier("profile.guestName")
                }
            }
            // Leaves room for the floating settings button.
            Spacer(minLength: 52)
        }
        .padding(.top, 2)
    }

    /// Decorative stack of record cards.
    private var recordCard: some View {
        let isGuest = libraries.current.scope == LibraryScope.guest
        return ZStack(alignment: .top) {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(ZJTheme.secondaryInk.opacity(0.3))
                .frame(height: 170)
                .padding(.leading, 34)
                .padding(.trailing, -6)
                .rotationEffect(.degrees(6))
                .offset(y: -6)
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(ZJTheme.secondaryInk)
                .frame(height: 170)
                .padding(.leading, 18)
                .padding(.trailing, 2)
                .rotationEffect(.degrees(3))
                .offset(y: 2)
            VStack(alignment: .leading) {
                HStack {
                    Text("ZHOUJI · LOCAL")
                        .font(.caption2.weight(.bold))
                        .tracking(2)
                        .foregroundStyle(ZJTheme.secondaryOnEmphasis)
                    Spacer()
                    Text(isGuest ? "游客记录" : "账户记录")
                        .font(.caption)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(ZJTheme.onEmphasis.opacity(0.14), in: Capsule())
                }
                Spacer()
                Text("MORE GOOD DAYS.")
                    .font(.title3.weight(.semibold))
                    .tracking(2.5)
            }
            .foregroundStyle(ZJTheme.onEmphasis)
            .padding(22)
            .frame(maxWidth: .infinity, minHeight: 170, maxHeight: 170)
            .background(ZJInkBlock(cornerRadius: 26))
            .offset(y: 12)
        }
        .frame(height: 196)
        .padding(.top, 6)
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }

    private var menu: some View {
        VStack(spacing: 10) {
            panelButton(.overview, title: "我的概况", detail: "累计完成、本周投入与完成率",
                            symbol: "chart.bar", isInk: true, identifier: "profile.overview")
            panelButton(.preferences, title: "偏好设置", detail: "账户、记录库与关于粥记",
                            symbol: "slider.horizontal.3", isInk: false, identifier: "profile.preferences")
        }
    }

    private func panelButton(_ panel: ProfilePanel, title: String, detail: String, symbol: String,
                                 isInk: Bool, identifier: String) -> some View {
        Button { presentedPanel = panel } label: {
            HStack(spacing: 14) {
                Image(systemName: symbol)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(isInk ? ZJTheme.onAccent : ZJTheme.ink)
                    .frame(width: 42, height: 42)
                    .background(isInk ? ZJTheme.accent : ZJTheme.mutedSurface, in: Circle())
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.body.weight(.bold))
                        .foregroundStyle(ZJTheme.ink)
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(ZJTheme.secondaryInk)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(ZJTheme.secondaryInk)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 68)
            .zjCard()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
    }

    private func metrics(secondsThisWeek: TimeInterval, completed: Int, rate: Int) -> some View {
        let tiles = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: 12))
            : AnyLayout(HStackLayout(spacing: 12))
        return VStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                Text("本周真实投入")
                    .font(.subheadline)
                    .foregroundStyle(ZJTheme.secondaryOnEmphasis)
                Text(ElapsedTimeText.string(for: secondsThisWeek))
                    .font(.system(size: 44, weight: .light, design: ZJTheme.numberDesign))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .accessibilityIdentifier("profile.weekFocus")
                Text("从周一 00:00 起，只计运行中的时间")
                    .font(.caption)
                    .foregroundStyle(ZJTheme.secondaryOnEmphasis)
            }
            .foregroundStyle(ZJTheme.onEmphasis)
            .padding(22)
            .frame(maxWidth: .infinity, minHeight: 180, alignment: .bottomLeading)
            .background(ZJInkBlock())
            tiles {
                metricTile(title: "累计完成", value: "\(completed) 件", symbol: "checkmark", identifier: "profile.completed")
                metricTile(title: "任务完成率", value: "\(rate)%", symbol: "chart.pie", identifier: "profile.completionRate")
            }
        }
    }

    private func metricTile(title: String, value: String, symbol: String, identifier: String) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(ZJTheme.ink)
                .frame(width: 40, height: 40)
                .background(ZJTheme.mutedSurface, in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(value)
                    .font(.system(size: 34, weight: .light, design: ZJTheme.numberDesign))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .foregroundStyle(ZJTheme.ink)
                    .accessibilityIdentifier(identifier)
                Text(title)
                    .font(.subheadline)
                    .foregroundStyle(ZJTheme.secondaryInk)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, minHeight: 160, alignment: .leading)
        .zjCard()
    }

    private var overview: some View {
        NavigationStack {
            TimelineView(.everyMinute) { minute in
                let duration = Result(catching: { try StatisticsService.weekDuration(sessions: sessions, containing: minute.date) })
                let completed = completedCount
                let rate = completionRate
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        ZJPageHeader(title: "我的概况", subtitle: "每一步，都算数。", identifier: "profile.overviewHeading")
                        switch duration {
                        case .failure(let error):
                            Text(error.localizedDescription).foregroundStyle(ZJTheme.secondaryInk)
                        case .success(let duration):
                            TimelineView(.periodic(from: .now, by: duration.isRunning ? 1 : 60)) { tick in
                                metrics(secondsThisWeek: duration.seconds(now: tick.date), completed: completed, rate: rate)
                            }
                        }
                    }
                    .padding(.horizontal, ZJTheme.pagePadding)
                    .padding(.top, 14)
                    .padding(.bottom, 24)
                }
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                ZJBackButton { presentedPanel = nil }
                    .accessibilityIdentifier("profile.closePanel")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, ZJTheme.pagePadding - 6)
                    .padding(.top, 6)
                    .background(ZJTheme.pageBackground)
            }
            .background(ZJTheme.pageBackground.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
        }
    }


}

private enum ProfilePanel: String, Identifiable {
    case overview, editProfile, preferences
    var id: String { rawValue }
}

private struct ProfilePreferencesView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(AccountStore.self) private var account
    @Environment(LocalLibraryStore.self) private var libraries
    @Query private var tasks: [TodoTask]
    @State private var isAboutPresented = false
    @State private var isProfileEditorPresented = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    ZJPageHeader(title: "偏好设置", identifier: "profile.preferencesHeading")
                    identityCard
                    settingsCard
                    sectionTitle("账户")
                    AccountControls()
                    sectionTitle("记录库")
                    LocalLibraryCard()
                    SyncSettingsCard()
                    AccountSessionActions()
                }
                .padding(.horizontal, ZJTheme.pagePadding)
                .padding(.top, 16)
                .padding(.bottom, 28)
            }
            .background(ZJTheme.pageBackground.ignoresSafeArea())
            .safeAreaInset(edge: .top, spacing: 0) {
                ZJBackButton(action: dismiss.callAsFunction)
                    .accessibilityIdentifier("profile.closePanel")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, ZJTheme.pagePadding - 6)
                    .padding(.top, 6)
                    .background(ZJTheme.pageBackground)
            }
            .toolbar(.hidden, for: .navigationBar)
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
                    ProfileAvatarView(avatar: ProfileAvatar(rawValue: profile.avatar ?? "") ?? .liuli)
                    VStack(alignment: .leading, spacing: 7) {
                        Text(profile.displayName)
                            .font(.title2.weight(.semibold))
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
            ProfileAvatarView(avatar: .liuli)

            VStack(alignment: .leading, spacing: 5) {
                Text(libraries.current.scope == LibraryScope.guest ? "游客模式" : "账户记录 · 离线")
                    .font(.title2.weight(.semibold))
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
            .padding(.horizontal, 14)
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(ZJTheme.titleFont(25, relativeTo: .title2).weight(.bold))
            .foregroundStyle(ZJTheme.ink)
            .padding(.top, 6)
            .accessibilityAddTraits(.isHeader)
    }

    private static var appVersion: String { ZJAppVersion.display }
}

struct ProfileSettingRow: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let title: String
    let detail: String
    let systemImage: String
    let showsChevron: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(ZJTheme.success)
                .frame(width: 32, height: 36)
                .accessibilityHidden(true)
            let layout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6))
                : AnyLayout(HStackLayout(spacing: 8))
            layout {
                Text(title)
                    .font(ZJTheme.titleFont(20, relativeTo: .headline).weight(.bold))
                    .foregroundStyle(ZJTheme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: 0) }
                Text(detail)
                    .font(ZJTheme.titleFont(14, relativeTo: .caption))
                    .foregroundStyle(ZJTheme.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.body.weight(.medium))
                    .foregroundStyle(ZJTheme.ink)
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 16)
        .frame(minHeight: 64)
        .contentShape(Rectangle())
    }
}

enum ZJAppVersion {
    static var display: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }
}

private struct AboutZhouJiView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    Text("关于粥记")
                        .font(ZJTheme.titleFont(32, relativeTo: .title).weight(.bold))
                        .accessibilityAddTraits(.isHeader)
                    VStack(spacing: 4) {
                        Text("粥记")
                            .font(ZJTheme.titleFont(62, relativeTo: .largeTitle).weight(.bold))
                        Text("一粥又一周")
                            .font(ZJTheme.titleFont(30, relativeTo: .title).weight(.bold))
                            .overlay(alignment: .bottom) {
                                Capsule().fill(ZJTheme.secondaryInk)
                                    .frame(height: 4)
                                    .rotationEffect(.degrees(-3))
                                    .offset(y: 7)
                                    .accessibilityHidden(true)
                            }
                    }
                    Text("版本 \(ZJAppVersion.display)")
                        .font(ZJTheme.titleFont(17, relativeTo: .footnote))
                        .foregroundStyle(ZJTheme.secondaryInk)
                        .accessibilityIdentifier("about.version")
                    Text("打开即做，记录真实投入。\n把重要的事，一件一件完成。")
                        .font(ZJTheme.titleFont(19, relativeTo: .body))
                        .foregroundStyle(ZJTheme.secondaryInk)
                        .lineSpacing(7)
                        .fixedSize(horizontal: false, vertical: true)
                    VStack(spacing: 8) {
                        HStack(spacing: 4) {
                            ZJIcon(systemName: "leaf.fill", size: 36)
                            ZJIcon(systemName: "star.fill", size: 26)
                        }
                        .accessibilityHidden(true)
                        Text("A LITTLE EVERYDAY,\nA BETTER WEEK.")
                            .font(ZJTheme.titleFont(13, relativeTo: .caption))
                            .tracking(1)
                    }
                    .padding(.top, 8)
                }
                .foregroundStyle(ZJTheme.ink)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, ZJTheme.pagePadding)
                .padding(.top, 12)
                .padding(.bottom, 28)
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                ZJBackButton(label: "完成", action: dismiss.callAsFunction)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, ZJTheme.pagePadding - 6)
                    .padding(.top, 6)
                    .background(ZJTheme.pageBackground)
            }
            .background(ZJTheme.pageBackground.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
        }
        .presentationBackground(ZJTheme.background)
    }
}

#Preview {
    let container = try! ModelContainer(for: Goal.self, TodoTask.self, TimingSession.self,
                                       configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    let libraries = try! LocalLibraryStore(guest: container, inMemory: true)
    ProfileView()
        .modelContainer(container)
        .environment(AccountStore())
        .environment(libraries)
}
