import SwiftData
import SwiftUI

struct RootTabView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(TimerController.self) private var timer
    @State private var selection: AppTab

    init() {
        _selection = State(initialValue: Self.debugInitialTab ?? .today)
    }

    var body: some View {
        TabView(selection: $selection) {
            TodayView()
                .tag(AppTab.today)
                .tabItem {
                    Label("今天", systemImage: "house")
                }

            GoalsView()
                .tag(AppTab.goals)
                .tabItem {
                    Label("目标", systemImage: "scope")
                }

            FocusView()
                .tag(AppTab.focus)
                .tabItem {
                    Label("专注", systemImage: "timer")
                }

            RecordsView()
                .tag(AppTab.records)
                .tabItem {
                    Label("记录", systemImage: "chart.bar")
                }
        }
        .toolbarBackground(ZJTheme.surface.opacity(0.97), for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
        .task {
            timer.configure(with: modelContext)
        }
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

private enum AppTab: String, Hashable {
    case today
    case goals
    case focus
    case records
}
