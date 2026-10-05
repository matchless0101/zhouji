import Foundation
import SwiftData
import Testing
import UIKit
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

    @Test func failedPauseResumeAndFinishRestoreFactsAndAllowRetry() throws {
        let context = try makeContext()
        context.autosaveEnabled = false
        var fails = false
        var now = Date(timeIntervalSince1970: 1000)
        let timer = TimerController(nowProvider: { now }, save: { context in
            if fails { throw CocoaError(.fileWriteOutOfSpace) }
            try context.save()
        })
        timer.configure(with: context)
        #expect(timer.requestStart(for: TodoTask(title: "保存失败")) == .started)
        let session = try #require(timer.activeSession)
        let initialData = session.activeIntervalsData
        now = Date(timeIntervalSince1970: 1010)
        fails = true
        #expect(!timer.pause())
        #expect(session.state == .running)
        #expect(session.runningStartedAt == Date(timeIntervalSince1970: 1000))
        #expect(session.activeIntervalsData == initialData)
        #expect(session.accumulatedSeconds == 0)
        #expect(!timer.finishActiveSession())
        #expect(timer.activeSession === session)
        #expect(session.state == .running && session.endedAt == nil)
        #expect(session.activeIntervalsData == initialData)
        fails = false
        #expect(timer.pause())
        let pausedData = session.activeIntervalsData
        now = Date(timeIntervalSince1970: 1020)
        fails = true
        #expect(!timer.resume())
        #expect(session.state == .paused && session.runningStartedAt == nil)
        #expect(session.activeIntervalsData == pausedData)
        #expect(session.accumulatedSeconds == 10)
        fails = false
        #expect(timer.resume())
        now = Date(timeIntervalSince1970: 1030)
        #expect(timer.finishActiveSession())
        #expect(session.accumulatedSeconds == 20)
        #expect(try session.activeIntervals.count == 2)
    }

    @Test func finishedCorruptHistoryDoesNotBlockRestoringActiveTimer() throws {
        let context = try makeContext()
        let old = try TimingSession(taskID: UUID(), taskTitleSnapshot: "旧历史",
            startedAt: Date(timeIntervalSince1970: 1000), state: .finished)
        old.activeIntervalsData = Data("broken".utf8)
        let active = try TimingSession(taskID: UUID(), taskTitleSnapshot: "正在做",
            startedAt: Date(timeIntervalSince1970: 2000), runningStartedAt: Date(timeIntervalSince1970: 2000), state: .running)
        context.insert(old)
        context.insert(active)
        try context.save()
        let timer = TimerController()
        timer.configure(with: context)
        #expect(timer.activeSession?.id == active.id)
        #expect(timer.errorMessage == nil)
        #expect(old.activeIntervalsData == Data("broken".utf8))
        #expect(throws: TimingDataError.self) { try old.activeIntervals }
    }

    @Test func failedDuplicateRepairRestoresFactsAndCanRetry() throws {
        let context = try makeContext()
        context.autosaveEnabled = false
        let older = try TimingSession(taskID: UUID(), taskTitleSnapshot: "旧计时",
            startedAt: Date(timeIntervalSince1970: 1000), runningStartedAt: Date(timeIntervalSince1970: 1000), state: .running)
        let newer = try TimingSession(taskID: UUID(), taskTitleSnapshot: "新计时",
            startedAt: Date(timeIntervalSince1970: 2000), state: .paused)
        context.insert(older)
        context.insert(newer)
        try context.save()
        let original = older.activeIntervalsData
        var fails = true
        let timer = TimerController(nowProvider: { Date(timeIntervalSince1970: 2010) }, save: { context in
            if fails { throw CocoaError(.fileWriteOutOfSpace) }
            try context.save()
        })
        timer.configure(with: context)
        #expect(timer.activeSession == nil && timer.errorMessage != nil)
        #expect(older.state == .running && older.endedAt == nil)
        #expect(older.runningStartedAt == Date(timeIntervalSince1970: 1000))
        #expect(older.accumulatedSeconds == 0 && older.activeIntervalsData == original)
        fails = false
        timer.reloadAfterBackupRestore()
        #expect(timer.activeSession?.id == newer.id && timer.errorMessage == nil)
        #expect(older.state == .finished)
        #expect(older.accumulatedSeconds == 1010)
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

@MainActor
struct TaskNavigationBackgroundTests {
    @Test func onlyTabSurfacesChangeWithoutRecoloringNestedNavigation() {
        let tab = UITabBarController()
        let host = UIViewController()
        let navigation = UINavigationController(rootViewController: UIViewController())
        host.addChild(navigation)
        navigation.didMove(toParent: host)
        tab.viewControllers = [host]
        tab.view.backgroundColor = .red
        host.view.backgroundColor = .blue
        navigation.view.backgroundColor = .green
        let destination = navigation.viewControllers[0]
        destination.view.backgroundColor = .yellow
        let paper = TaskNavigationBackground.PaperController()
        destination.addChild(paper)
        paper.didMove(toParent: destination)
        #expect(tab.view.backgroundColor == UIColor(ZJTheme.background))
        #expect(host.view.backgroundColor == UIColor(ZJTheme.background))
        #expect(navigation.view.backgroundColor == .green)
        #expect(destination.view.backgroundColor == .yellow)
    }
}
