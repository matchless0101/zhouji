import SwiftData
import SwiftUI
import AuthenticationServices

@main
struct ZhouJiApp: App {
    @State private var timerController = TimerController()
    @State private var accountStore = AccountStore()
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("appAppearance") private var appearanceRawValue = AppAppearance.system.rawValue

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
            let container = try ModelContainer(for: schema, configurations: [configuration])
            #if DEBUG
            if usesInMemoryStore, ProcessInfo.processInfo.arguments.contains("-ZJPreviewSampleData") {
                try insertPreviewSampleData(in: container.mainContext)
            }
            #endif
            return container
        } catch {
            fatalError("无法创建粥记本地数据库：\(error.localizedDescription)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environment(timerController)
                .environment(accountStore)
                .task { await accountStore.restore() }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active { Task { await accountStore.restore() } }
                }
                .onReceive(NotificationCenter.default.publisher(for: ASAuthorizationAppleIDProvider.credentialRevokedNotification)) { _ in
                    Task { await accountStore.credentialRevoked() }
                }
                .onOpenURL { accountStore.handleWeChat(url: $0) }
                .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { accountStore.handleWeChat(activity: $0) }
                .tint(ZJTheme.accent)
                .preferredColorScheme(
                    (AppAppearance(rawValue: appearanceRawValue) ?? .system).colorScheme
                )
        }
        .modelContainer(sharedModelContainer)
    }
    #if DEBUG
    /// Visual-review fixtures are opt-in and can only be inserted into a temporary store.
    @MainActor
    private static func insertPreviewSampleData(in context: ModelContext) throws {
        let now = Date.now
        let today = Calendar.current.startOfDay(for: now)
        let earlier = today.addingTimeInterval(-3_600)
        let weekStart = DateBoundaries.mondayWeek(containing: now).start
        let thesis = Goal(name: "论文", iconName: GoalIcon.book.rawValue, createdAt: now.addingTimeInterval(-30))
        let career = Goal(name: "求职", iconName: GoalIcon.work.rawValue, createdAt: now.addingTimeInterval(-20))
        let digital = Goal(name: "iOS App", iconName: GoalIcon.digital.rawValue, createdAt: now.addingTimeInterval(-10))
        for goal in [thesis, career, digital] { context.insert(goal) }
        let pending = [
            TodoTask(title: "整理开题资料", createdAt: now.addingTimeInterval(-30), goal: thesis),
            TodoTask(title: "投递实习简历", createdAt: now.addingTimeInterval(-20), goal: career),
            TodoTask(title: "练习 SwiftUI", createdAt: now.addingTimeInterval(-10), goal: digital)
        ]
        for task in pending { context.insert(task) }
        for (goal, titles) in [(thesis, ["确定论文方向", "收集参考文献"]),
                               (career, ["整理个人简历"]),
                               (digital, ["梳理产品需求", "画出页面草图"])] {
            for title in titles { context.insert(TodoTask(title: title, completedAt: earlier, goal: goal)) }
        }
        context.insert(TodoTask(title: "晨间阅读", completedAt: today.addingTimeInterval(60)))
        context.insert(TodoTask(title: "回复师消息", completedAt: today.addingTimeInterval(120)))
        func session(_ task: TodoTask, start: Date, minutes: Double, goal: Goal?) {
            let end = start.addingTimeInterval(minutes * 60)
            context.insert(TimingSession(
                taskID: task.id, taskTitleSnapshot: task.title,
                goalIDSnapshot: goal?.id, goalNameSnapshot: goal?.name,
                startedAt: start, endedAt: end,
                activeIntervals: [TimingInterval(startedAt: start, endedAt: end)],
                accumulatedSeconds: minutes * 60, state: .finished
            ))
        }
        session(pending[0], start: today.addingTimeInterval(3_600), minutes: 62, goal: thesis)
        session(pending[0], start: weekStart.addingTimeInterval(3_600), minutes: 128, goal: thesis)
        session(pending[1], start: weekStart.addingTimeInterval(12_000), minutes: 100, goal: career)
        session(pending[2], start: weekStart.addingTimeInterval(20_000), minutes: 65, goal: digital)
        session(pending[2], start: today.addingTimeInterval(12_000), minutes: 40, goal: nil)
        try context.save()
    }
    #endif

}
