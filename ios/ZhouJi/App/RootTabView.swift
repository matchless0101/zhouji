import SwiftData
import SwiftUI

struct RootTabView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(TimerController.self) private var timer
    @Environment(LocalLibraryStore.self) private var libraries
    @Binding private var selection: AppTab

    static var initialTab: AppTab { debugInitialTab ?? .today }

    init(selection: Binding<AppTab>) {
        _selection = selection
    }

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $selection) {
                TodayView()
                    .toolbar(.hidden, for: .tabBar)
                    .tag(AppTab.today)
                    .tabItem {
                        Label("今天", systemImage: "house")
                    }

                GoalsView()
                    .toolbar(.hidden, for: .tabBar)
                    .tag(AppTab.goals)
                    .tabItem {
                        Label("目标", systemImage: "scope")
                    }

                RecordsView()
                    .toolbar(.hidden, for: .tabBar)
                    .tag(AppTab.records)
                    .tabItem {
                        Label("记录", systemImage: "chart.bar")
                    }

                ProfileView()
                    .toolbar(.hidden, for: .tabBar)
                    .tag(AppTab.profile)
                    .tabItem {
                        Label("我的", systemImage: "person")
                    }
            }
            if libraries.current.scope != LibraryScope.guest && libraries.authenticatedScope == nil {
                Text("账户本机记录 · 请重新登录原账户")
                    .font(.caption).foregroundStyle(ZJTheme.secondaryInk)
            } else if libraries.current.scope == LibraryScope.guest && libraries.authenticatedScope != nil {
                Text("正在查看游客记录 · 未合并到账户")
                    .font(.caption).foregroundStyle(ZJTheme.secondaryInk)
            }
            navigationBar
        }
        .background(ZJTheme.pageBackground.ignoresSafeArea())
        .ignoresSafeArea(.container, edges: .bottom)
        .task {
            timer.configure(with: modelContext)
        }
    }

    private var navigationBar: some View {
        HStack(spacing: 0) {
            ForEach(AppTab.allCases, id: \.self) { tab in
                Button {
                    selection = tab
                } label: {
                    VStack(spacing: 5) {
                        Image(systemName: selection == tab ? tab.selectedSymbol : tab.symbol)
                            .symbolVariant(.none)
                            .font(.system(size: 25, weight: .medium))
                            .frame(height: 28)
                        Text(tab.title)
                            .font(.caption)
                    }
                    .foregroundStyle(selection == tab ? ZJTheme.accent : ZJTheme.secondaryInk)
                    .frame(maxWidth: .infinity)
                    .frame(height: 72)
                    .background {
                        if selection == tab {
                            Circle()
                                .fill(RadialGradient(
                                    colors: [ZJTheme.accentSoft, ZJTheme.accentSoft.opacity(0.35)],
                                    center: .center, startRadius: 16, endRadius: 40
                                ))
                                .overlay { Circle().stroke(ZJTheme.surface, lineWidth: 1.5) }
                                .frame(width: 76, height: 76)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tab.title)
                .accessibilityIdentifier("tab.\(tab.rawValue)")
                .accessibilityAddTraits(selection == tab ? .isSelected : [])
            }
        }
        .padding(4)
        .background(ZJTheme.surface.opacity(0.96), in: Capsule())
        .overlay { Capsule().stroke(ZJTheme.surface, lineWidth: 1.5) }
        .shadow(color: ZJTheme.secondaryInk.opacity(0.08), radius: 16, y: 5)
        .padding(.horizontal, 10)
        .padding(.bottom, 12)
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("底部导航")
    }

    private static var debugInitialTab: AppTab? {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        guard let flagIndex = arguments.firstIndex(of: "-ZJInitialTab"),
              arguments.indices.contains(flagIndex + 1) else {
            return nil
        }
        return AppTab(rawValue: arguments[flagIndex + 1])
        #else
        return nil
        #endif
    }
}

enum AppTab: String, Hashable, CaseIterable {
    case today
    case goals
    case records
    case profile

    var title: String {
        switch self {
        case .today: "今天"
        case .goals: "目标"
        case .records: "记录"
        case .profile: "我的"
        }
    }

    var symbol: String {
        switch self {
        case .today: "house"
        case .goals: "target"
        case .records: "chart.bar"
        case .profile: "person"
        }
    }

    var selectedSymbol: String {
        switch self {
        case .today: "house.fill"
        case .records: "chart.bar.fill"
        default: symbol
        }
    }
}
