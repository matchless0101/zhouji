import Foundation
import SwiftData
import Testing
@testable import ZhouJi

@MainActor
struct TimerControllerTests {
    @Test
    func pauseAndResumePersistSeparateRunningIntervals() throws {
        let context = try makeContext()
        var now = Date(timeIntervalSince1970: 1_000)
        let timer = TimerController(nowProvider: { now })
        timer.configure(with: context)
        let task = TodoTask(title: "写论文", createdAt: now)

        #expect(timer.requestStart(for: task) == .started)

        now = now.addingTimeInterval(10)
        #expect(timer.pause())
        #expect(timer.elapsed(at: now) == 10)

        now = now.addingTimeInterval(50)
        #expect(timer.resume())

        now = now.addingTimeInterval(5)
        #expect(timer.finishActiveSession())
        #expect(timer.activeSession == nil)

        let sessions = try context.fetch(FetchDescriptor<TimingSession>())
        let session = try #require(sessions.first)
        #expect(session.state == .finished)
        #expect(session.accumulatedSeconds == 15)
        #expect(session.activeIntervals.count == 2)
    }

    @Test
    func secondTaskRequiresExplicitSwitch() throws {
        let context = try makeContext()
        let timer = TimerController(nowProvider: { Date(timeIntervalSince1970: 1_000) })
        timer.configure(with: context)
        let first = TodoTask(title: "写论文")
        let second = TodoTask(title: "刷算法题")

        #expect(timer.requestStart(for: first) == .started)
        #expect(
            timer.requestStart(for: second)
                == .confirmSwitch(currentTaskTitle: "写论文")
        )
    }

    private func makeContext() throws -> ModelContext {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: TodoTask.self,
            Goal.self,
            TimingSession.self,
            configurations: configuration
        )
        return ModelContext(container)
    }
}
