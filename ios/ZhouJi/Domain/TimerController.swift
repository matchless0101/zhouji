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
    @ObservationIgnored private var storageFailure: String?

    @ObservationIgnored private var modelContext: ModelContext?
    @ObservationIgnored private var nowProvider: () -> Date

    @ObservationIgnored private let save: (ModelContext) throws -> Void

    init(nowProvider: @escaping () -> Date = Date.init,
         save: @escaping (ModelContext) throws -> Void = { try $0.save() }) {
        self.nowProvider = nowProvider
        self.save = save
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
        if let storageFailure { errorMessage = storageFailure; return .failed }
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

        return updateSession(session) {
            try closeRunningInterval(for: session, at: nowProvider())
            session.state = .paused
        }
    }

    @discardableResult
    func resume() -> Bool {
        guard let session = activeSession, session.state == .paused else { return true }
        return updateSession(session) {
            _ = try session.activeIntervals
            session.runningStartedAt = nowProvider()
            session.state = .running
        }
    }

    @discardableResult
    func finishActiveSession() -> Bool {
        guard let session = activeSession else { return true }
        guard updateSession(session, changes: {
            _ = try session.activeIntervals
            let now = nowProvider()
            if session.state == .running {
                try closeRunningInterval(for: session, at: now)
            }
            session.state = .finished
            session.endedAt = now
            session.runningStartedAt = nil
        }) else { return false }
        activeSession = nil
        return true
    }

    private func updateSession(_ session: TimingSession, changes: () throws -> Void) -> Bool {
        let previous = SessionState(session)
        do { try changes() }
        catch {
            previous.restore(session)
            errorMessage = error.localizedDescription
            return false
        }
        guard saveContext() else {
            previous.restore(session)
            return false
        }
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
        let session: TimingSession
        do { session = try TimingSession(
            taskID: task.id,
            taskTitleSnapshot: task.title,
            goalIDSnapshot: task.goal?.id,
            goalNameSnapshot: task.goal?.name,
            startedAt: now,
            runningStartedAt: now,
            state: .running
        ) } catch { errorMessage = error.localizedDescription; return false }

        modelContext.insert(session)
        guard saveContext() else {
            modelContext.delete(session)
            return false
        }

        activeSession = session
        return true
    }

    private func closeRunningInterval(for session: TimingSession, at proposedEnd: Date) throws {
        guard let startedAt = session.runningStartedAt else { return }
        let endedAt = max(proposedEnd, startedAt)
        let interval = TimingInterval(startedAt: startedAt, endedAt: endedAt)
        var intervals = try session.activeIntervals
        intervals.append(interval)
        try session.setActiveIntervals(intervals)
        session.accumulatedSeconds += interval.duration
        session.runningStartedAt = nil
    }

    private func restorePersistedSession() {
        guard let modelContext else { return }

        do {
            let finished = TimingSessionState.finished.rawValue
            let descriptor = FetchDescriptor<TimingSession>(
                predicate: #Predicate { $0.stateRawValue != finished },
                sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
            )
            let unfinished = try modelContext.fetch(descriptor)
            for session in unfinished { _ = try session.activeIntervals }

            if unfinished.count > 1 {
                let duplicates = Array(unfinished.dropFirst())
                let previous = duplicates.map(SessionState.init)
                do {
                    let repairDate = nowProvider()
                    for duplicate in duplicates {
                        if duplicate.state == .running {
                            try closeRunningInterval(for: duplicate, at: repairDate)
                        }
                        duplicate.state = .finished
                        duplicate.endedAt = repairDate
                        duplicate.runningStartedAt = nil
                    }
                    try save(modelContext)
                } catch {
                    for (session, state) in zip(duplicates, previous) { state.restore(session) }
                    throw error
                }
            }
            activeSession = unfinished.first
            storageFailure = nil
            errorMessage = nil
        } catch {
            activeSession = nil
            storageFailure = "未能恢复上次计时：\(error.localizedDescription)"
            errorMessage = storageFailure
        }
    }

    private func saveContext() -> Bool {
        guard let modelContext else {
            errorMessage = "本地数据尚未准备好，请稍后重试。"
            return false
        }

        do {
            try save(modelContext)
            return true
        } catch {
            errorMessage = "未能保存计时：\(error.localizedDescription)"
            return false
        }
    }
}

private struct SessionState {
    let intervals: Data
    let seconds: TimeInterval
    let runningStart: Date?
    let end: Date?
    let state: String

    init(_ session: TimingSession) {
        intervals = session.activeIntervalsData
        seconds = session.accumulatedSeconds
        runningStart = session.runningStartedAt
        end = session.endedAt
        state = session.stateRawValue
    }

    func restore(_ session: TimingSession) {
        session.activeIntervalsData = intervals
        session.accumulatedSeconds = seconds
        session.runningStartedAt = runningStart
        session.endedAt = end
        session.stateRawValue = state
    }
}
