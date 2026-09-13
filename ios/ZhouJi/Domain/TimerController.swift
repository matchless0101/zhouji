import Foundation
import Observation
import SwiftData

enum TimerStartDecision: Equatable {
    case started
    case showCurrent
    case confirmSwitch(currentTaskTitle: String)
    case failed
}

@MainActor
@Observable
final class TimerController {
    private(set) var activeSession: TimingSession?
    private(set) var errorMessage: String?

    @ObservationIgnored private var modelContext: ModelContext?
    @ObservationIgnored private var nowProvider: () -> Date

    init(nowProvider: @escaping () -> Date = Date.init) {
        self.nowProvider = nowProvider
    }

    var activeTaskID: UUID? {
        activeSession?.taskID
    }

    var isRunning: Bool {
        activeSession?.state == .running
    }

    func configure(with context: ModelContext) {
        guard modelContext == nil else { return }
        modelContext = context
        restorePersistedSession()
    }

    func reloadAfterBackupRestore() { restorePersistedSession() }

    func requestStart(for task: TodoTask) -> TimerStartDecision {
        guard let activeSession else {
            return start(task: task) ? .started : .failed
        }

        if activeSession.taskID == task.id {
            return .showCurrent
        }

        return .confirmSwitch(currentTaskTitle: activeSession.taskTitleSnapshot)
    }

    @discardableResult
    func switchTo(_ task: TodoTask) -> Bool {
        guard finishActiveSession() else { return false }
        return start(task: task)
    }

    @discardableResult
    func pause() -> Bool {
        guard let session = activeSession, session.state == .running else {
            return true
        }

        closeRunningInterval(for: session, at: nowProvider())
        session.state = .paused
        return saveContext()
    }

    @discardableResult
    func resume() -> Bool {
        guard let session = activeSession, session.state == .paused else {
            return true
        }

        session.runningStartedAt = nowProvider()
        session.state = .running
        return saveContext()
    }

    @discardableResult
    func finishActiveSession() -> Bool {
        guard let session = activeSession else { return true }

        let now = nowProvider()
        if session.state == .running {
            closeRunningInterval(for: session, at: now)
        }

        session.state = .finished
        session.endedAt = now
        session.runningStartedAt = nil

        guard saveContext() else { return false }
        activeSession = nil
        return true
    }

    func elapsed(at date: Date) -> TimeInterval {
        guard let session = activeSession else { return 0 }
        return TimerMath.elapsed(
            accumulatedSeconds: session.accumulatedSeconds,
            runningStartedAt: session.state == .running ? session.runningStartedAt : nil,
            now: date
        )
    }

    func clearError() {
        errorMessage = nil
    }

    private func start(task: TodoTask) -> Bool {
        guard let modelContext else {
            errorMessage = "本地数据尚未准备好，请稍后重试。"
            return false
        }

        let now = nowProvider()
        let session = TimingSession(
            taskID: task.id,
            taskTitleSnapshot: task.title,
            goalIDSnapshot: task.goal?.id,
            goalNameSnapshot: task.goal?.name,
            startedAt: now,
            runningStartedAt: now,
            state: .running
        )

        modelContext.insert(session)
        guard saveContext() else {
            modelContext.delete(session)
            return false
        }

        activeSession = session
        return true
    }

    private func closeRunningInterval(for session: TimingSession, at proposedEnd: Date) {
        guard let startedAt = session.runningStartedAt else { return }
        let endedAt = max(proposedEnd, startedAt)
        let interval = TimingInterval(startedAt: startedAt, endedAt: endedAt)
        session.activeIntervals.append(interval)
        session.accumulatedSeconds += interval.duration
        session.runningStartedAt = nil
    }

    private func restorePersistedSession() {
        guard let modelContext else { return }

        do {
            let descriptor = FetchDescriptor<TimingSession>(
                sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
            )
            let unfinished = try modelContext.fetch(descriptor).filter {
                $0.state != .finished
            }

            activeSession = unfinished.first

            if unfinished.count > 1 {
                let repairDate = nowProvider()
                for duplicate in unfinished.dropFirst() {
                    if duplicate.state == .running {
                        closeRunningInterval(for: duplicate, at: repairDate)
                    }
                    duplicate.state = .finished
                    duplicate.endedAt = repairDate
                    duplicate.runningStartedAt = nil
                }
                try modelContext.save()
            }
        } catch {
            errorMessage = "未能恢复上次计时：\(error.localizedDescription)"
        }
    }

    private func saveContext() -> Bool {
        guard let modelContext else {
            errorMessage = "本地数据尚未准备好，请稍后重试。"
            return false
        }

        do {
            try modelContext.save()
            return true
        } catch {
            errorMessage = "未能保存计时：\(error.localizedDescription)"
            return false
        }
    }
}
