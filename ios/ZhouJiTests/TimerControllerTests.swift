import Foundation
import SwiftData
import Testing
@testable import ZhouJi

@MainActor
struct TimerControllerTests {
    @Test func corruptIntervalsBlockPauseWithoutChangingStoredFacts() throws {
        let context = try makeContext()
        let timer = TimerController(nowProvider: { Date(timeIntervalSince1970: 2000) })
        timer.configure(with: context)
        let task = TodoTask(title: "保护坏数据")
        #expect(timer.requestStart(for: task) == .started)
        let session = try #require(timer.activeSession)
        session.activeIntervalsData = Data("broken".utf8)
        #expect(!timer.pause())
        #expect(timer.errorMessage != nil)
        #expect(session.state == .running)
        #expect(session.runningStartedAt == Date(timeIntervalSince1970: 2000))
        #expect(session.activeIntervalsData == Data("broken".utf8))
    }

    @Test func unknownSavedStateBlocksNewTimer() throws {
        let context = try makeContext()
        let session = try TimingSession(taskID: UUID(), taskTitleSnapshot: "未知状态",
            startedAt: Date(timeIntervalSince1970: 1000), state: .paused)
        session.stateRawValue = "broken"
        context.insert(session)
        try context.save()
        let timer = TimerController()
        timer.configure(with: context)
        #expect(timer.errorMessage != nil)
        #expect(timer.requestStart(for: TodoTask(title: "不能覆盖")) == .failed)
        #expect(session.stateRawValue == "broken")
    }

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
        #expect(try session.activeIntervals.count == 2)
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
