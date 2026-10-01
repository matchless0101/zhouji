import SwiftData
import SwiftUI

struct RootTabView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(TimerController.self) private var timer
    @Environment(LocalLibraryStore.self) private var libraries
    @Binding private var selection: AppTab
    @State private var todayPath: [TodayDestination] = []

    private var isEditingTask: Bool {
        selection == .today && !todayPath.isEmpty
    }

    static var initialTab: AppTab { debugInitialTab ?? .today }

    init(selection: Binding<AppTab>) {
        _selection = selection
    }

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $selection) {
                TodayView(navigationPath: $todayPath)
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

                CalendarView()
                    .toolbar(.hidden, for: .tabBar)
                    .tag(AppTab.calendar)
                    .tabItem {
                        Label("日历", systemImage: "calendar")
                    }

                ProfileView()
                    .toolbar(.hidden, for: .tabBar)
                    .tag(AppTab.profile)
                    .tabItem {
                        Label("我的", systemImage: "person")
                    }
            }
            if !isEditingTask {
                if libraries.current.scope != LibraryScope.guest && libraries.authenticatedScope == nil {
                    Text("账户本机记录 · 请重新登录原账户")
                        .font(.caption).foregroundStyle(ZJTheme.secondaryInk)
                } else if libraries.current.scope == LibraryScope.guest && libraries.authenticatedScope != nil {
                    Text("正在查看游客记录 · 未合并到账户")
                        .font(.caption).foregroundStyle(ZJTheme.secondaryInk)
                }
                navigationBar
            }
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
                    ZJIcon(systemName: tab.symbol, size: 40,
                           tint: selection == tab ? ZJTheme.accent : ZJTheme.secondaryInk)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tab.title)
                .accessibilityIdentifier("tab.\(tab.rawValue)")
                .accessibilityAddTraits(selection == tab ? .isSelected : [])
            }
        }
        .padding(.top, 4)
        .padding(.bottom, 24)
        .background(ZJTheme.surface)
        .overlay(alignment: .top) { ZJTheme.divider.opacity(0.45).frame(height: 0.5) }
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
    case calendar
    case profile

    var title: String {
        switch self {
        case .today: "今天"
        case .goals: "目标"
        case .calendar: "日历"
        case .profile: "我的"
        }
    }

    var symbol: String {
        switch self {
        case .today: "house"
        case .goals: "target"
        case .calendar: "calendar"
        case .profile: "person"
        }
    }

}
