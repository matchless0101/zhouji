import SwiftData
import SwiftUI

@main
struct ZhouJiApp: App {
    @State private var timerController = TimerController()

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Goal.self,
            TodoTask.self,
            TimingSession.self
        ])

        #if DEBUG
        let usesInMemoryStore = ProcessInfo.processInfo.arguments.contains("-ZJInMemoryStore")
        #else
        let usesInMemoryStore = false
        #endif
        let configuration = ModelConfiguration(isStoredInMemoryOnly: usesInMemoryStore)

        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("无法创建粥记本地数据库：\(error.localizedDescription)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environment(timerController)
                .tint(ZJTheme.accent)
        }
        .modelContainer(sharedModelContainer)
    }
}
