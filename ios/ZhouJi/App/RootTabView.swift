import SwiftData
import SwiftUI

struct RootTabView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(TimerController.self) private var timer
    @Environment(LocalLibraryStore.self) private var libraries
    @Binding private var selection: AppTab
    @State private var todayPath: [TodayDestination] = []
    @State private var goalsPath: [GoalDestination] = []

    private var isEditingTask: Bool {
        (selection == .today && !todayPath.isEmpty)
            || (selection == .goals && goalsPath.last?.isSettings == true)
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

                GoalsView(navigationPath: $goalsPath)
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

    @ViewBuilder
    private var navigationBar: some View {
        if ZJTheme.style == .mono {
            floatingNavigationBar
        } else {
            stripNavigationBar
        }
    }

    /// Mono floats a labelled capsule above the page with the add action in its center.
    private var floatingNavigationBar: some View {
        HStack(spacing: 2) {
            ForEach(AppTab.allCases, id: \.self) { tab in
                if tab == .calendar { addTaskButton }
                floatingTab(tab)
            }
        }
        .padding(8)
        .background(ZJTheme.surface, in: Capsule())
        .shadow(color: .black.opacity(0.10), radius: 20, x: 0, y: 10)
        .shadow(color: .black.opacity(0.05), radius: 3, x: 0, y: 1)
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 24)
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("底部导航")
    }

    private func floatingTab(_ tab: AppTab) -> some View {
        let isSelected = selection == tab
        return Button {
            selection = tab
        } label: {
            VStack(spacing: 3) {
                Image(systemName: tab.symbol)
                    .font(.system(size: 19, weight: isSelected ? .semibold : .regular))
                Text(tab.title)
                    .font(.caption2.weight(isSelected ? .bold : .medium))
                    .lineLimit(1)
            }
            .foregroundStyle(isSelected ? ZJTheme.ink : ZJTheme.secondaryInk)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background {
                if isSelected { Capsule().fill(ZJTheme.mutedSurface) }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tab.title)
        .accessibilityIdentifier("tab.\(tab.rawValue)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var addTaskButton: some View {
        Button {
            selection = .today
            todayPath = [.newTask]
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(ZJTheme.onAccent)
                .frame(width: 52, height: 52)
                .background(ZJTheme.accent, in: Circle())
                .shadow(color: .black.opacity(0.25), radius: 9, x: 0, y: 4)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 4)
        .accessibilityLabel("添加任务")
        .accessibilityIdentifier("tab.addTask")
    }

    private var stripNavigationBar: some View {
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
