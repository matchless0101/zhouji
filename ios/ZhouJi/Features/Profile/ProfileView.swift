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
                    ZJIcon(systemName: "gearshape", size: 40)
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
                case .editProfile:
                    if let profile = account.account { ProfileEditor(profile: profile) }
                }
            }
        }
    }

    private var header: some View {
        VStack(spacing: 12) {
            if let profile = account.account {
                let avatar = ProfileAvatar(rawValue: profile.avatar ?? "") ?? .liuli
                Button { presentedPanel = .editProfile } label: {
                    VStack(spacing: 12) {
                        ProfileAvatarView(avatar: avatar, size: dynamicTypeSize.isAccessibilitySize ? 88 : 112)
                        Text(profile.displayName)
                            .font(.title.weight(.semibold))
                            .foregroundStyle(ZJTheme.ink)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                        Label(profile.providerName, systemImage: profile.providerIcon)
                            .font(.caption)
                            .foregroundStyle(ZJTheme.secondaryInk)
                        Text("编辑个人资料")
                            .font(ZJTheme.handwriting(17, relativeTo: .subheadline))
                            .foregroundStyle(ZJTheme.secondaryInk)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(account.isBusy)
                .accessibilityLabel("\(profile.displayName)，编辑个人资料")
                .accessibilityValue("头像：\(avatar.title)")
                .accessibilityIdentifier("profile.identity")
            } else {
                ProfileAvatarView(avatar: .liuli, size: dynamicTypeSize.isAccessibilitySize ? 88 : 112)
                Text(libraries.current.scope == LibraryScope.guest ? "游客模式" : "账户记录 · 离线")
                    .font(.title.weight(.semibold))
                    .foregroundStyle(ZJTheme.ink)
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("profile.guestName")
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, dynamicTypeSize.isAccessibilitySize ? 42 : 22)
    }

    private var menuCard: some View {
        VStack(spacing: 0) {
            panelButton(.overview, title: "我的概况", symbol: "star.fill", identifier: "profile.overview")
            menuDivider
            panelButton(.preferences, title: "偏好设置", symbol: "leaf.fill", identifier: "profile.preferences")
        }
        .zjCard()
    }

    private var menuDivider: some View {
        Divider().overlay(ZJTheme.divider.opacity(0.7)).padding(.horizontal, 18)
    }

    private func panelButton(_ panel: ProfilePanel, title: String, symbol: String, identifier: String) -> some View {
        Button { presentedPanel = panel } label: {
            HStack(spacing: 16) {
                ZJIcon(systemName: symbol, size: 40).frame(width: 32)
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
        ZStack(alignment: .bottomTrailing) {
            Image("LiuliPostcard")
                .resizable()
                .scaledToFit()
            Text("MORE\nGOOD\nDAYS.")
                .font(ZJTheme.handwriting(15, relativeTo: .body))
                .tracking(1)
                .lineSpacing(2)
                .multilineTextAlignment(.center)
                .foregroundStyle(ZJTheme.ink)
                .frame(width: 78)
                .rotationEffect(.degrees(7))
                .padding(.trailing, 7)
                .padding(.bottom, 26)
        }
        .aspectRatio(4 / 3, contentMode: .fit)
        .frame(maxWidth: 300)
        .frame(maxWidth: .infinity)
        .padding(.top, 10)
        .padding(.bottom, 18)
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }

    private var overview: some View {
        NavigationStack {
            TimelineView(.everyMinute) { minute in
                let duration = Result(catching: { try StatisticsService.weekDuration(sessions: sessions, containing: minute.date) })
                let completed = completedCount
                let rate = completionRate
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        ZJPaperHeader(title: "我的概况", subtitle: "每一步，都算数。", illustration: "LiuliWriting", identifier: "profile.overviewHeading")
                        switch duration {
                        case .failure(let error):
                            Text(error.localizedDescription).foregroundStyle(ZJTheme.secondaryInk)
                        case .success(let duration):
                            TimelineView(.periodic(from: .now, by: duration.isRunning ? 1 : 60)) { tick in
                                metrics(secondsThisWeek: duration.seconds(now: tick.date), completed: completed, rate: rate)
                            }
                        }
                        if !dynamicTypeSize.isAccessibilitySize {
                            Image(decorative: "LiuliOverview")
                                .resizable()
                                .scaledToFit()
                                .allowsHitTesting(false)
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

    private func metrics(secondsThisWeek: TimeInterval, completed: Int, rate: Int) -> some View {
        VStack(spacing: 0) {
            ProfileMetricRow(title: "累计完成", value: "\(completed) 件", detail: "每一步都算数", systemImage: "checkmark.circle.fill", identifier: "profile.completed")
            Divider().overlay(ZJTheme.divider)
            ProfileMetricRow(title: "本周专注", value: ElapsedTimeText.string(for: secondsThisWeek), detail: "来自真实计时", systemImage: "clock.fill", identifier: "profile.weekFocus")
            Divider().overlay(ZJTheme.divider)
            ProfileMetricRow(title: "任务完成率", value: "\(rate)%", detail: "当前任务进度", systemImage: "leaf.fill", identifier: "profile.completionRate")
        }
        .padding(.horizontal, 14)
        .zjPaperCard()
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
                    ZJPaperHeader(title: "偏好设置", illustration: "LiuliPreferences", identifier: "profile.preferencesHeading")
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
                .zjPaperCard()
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
        .zjPaperCard()
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
        .zjPaperCard()
    }

    private var settingDivider: some View {
        Divider()
            .overlay(ZJTheme.divider)
            .padding(.horizontal, 14)
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(ZJTheme.handwriting(25, relativeTo: .title2).weight(.bold))
            .foregroundStyle(ZJTheme.ink)
            .padding(.top, 6)
            .accessibilityAddTraits(.isHeader)
    }

    private static var appVersion: String { ZJAppVersion.display }
}

private struct ProfileMetricRow: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let title: String
    let value: String
    let detail: String
    let systemImage: String
    let identifier: String

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
            : AnyLayout(HStackLayout(spacing: 10))
        layout {
            HStack(spacing: 10) {
                ZJIcon(systemName: systemImage, size: 48, tint: ZJTheme.success)
                VStack(alignment: .leading, spacing: 6) {
                    Text(title)
                        .font(ZJTheme.handwriting(20, relativeTo: .headline).weight(.bold))
                        .fixedSize(horizontal: false, vertical: true)
                    Text(detail)
                        .font(ZJTheme.handwriting(15, relativeTo: .caption))
                        .foregroundStyle(ZJTheme.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Text(value)
                .font(.system(.title, design: .rounded, weight: .semibold))
                .monospacedDigit()
                .minimumScaleFactor(0.65)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                .fixedSize(horizontal: false, vertical: true)
                .layoutPriority(1)
                .accessibilityIdentifier(identifier)
        }
        .foregroundStyle(ZJTheme.ink)
        .padding(.vertical, 26)
    }
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
                    .font(ZJTheme.handwriting(20, relativeTo: .headline).weight(.bold))
                    .foregroundStyle(ZJTheme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: 0) }
                Text(detail)
                    .font(ZJTheme.handwriting(14, relativeTo: .caption))
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
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    Text("关于粥记")
                        .font(ZJTheme.handwriting(32, relativeTo: .title).weight(.bold))
                        .accessibilityAddTraits(.isHeader)
                    if !dynamicTypeSize.isAccessibilitySize {
                        Image(decorative: "LiuliAbout")
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: 300)
                            .allowsHitTesting(false)
                    }
                    VStack(spacing: 4) {
                        Text("粥记")
                            .font(ZJTheme.handwriting(62, relativeTo: .largeTitle).weight(.bold))
                        Text("一粥又一周")
                            .font(ZJTheme.handwriting(30, relativeTo: .title).weight(.bold))
                            .overlay(alignment: .bottom) {
                                Capsule().fill(Color(red: 0.86, green: 0.65, blue: 0.29))
                                    .overlay { ZJInkGrain(count: 250).clipShape(Capsule()) }
                                    .frame(height: 4)
                                    .rotationEffect(.degrees(-3))
                                    .offset(y: 7)
                                    .accessibilityHidden(true)
                            }
                    }
                    Text("版本 \(ZJAppVersion.display)")
                        .font(ZJTheme.handwriting(17, relativeTo: .footnote))
                        .foregroundStyle(ZJTheme.secondaryInk)
                        .accessibilityIdentifier("about.version")
                    Text("打开即做，记录真实投入。\n把重要的事，一件一件完成。")
                        .font(ZJTheme.handwriting(19, relativeTo: .body))
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
                            .font(ZJTheme.handwriting(13, relativeTo: .caption))
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
