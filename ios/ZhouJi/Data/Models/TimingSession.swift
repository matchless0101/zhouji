import Foundation
import SwiftData

struct TimingInterval: Codable, Hashable, Sendable {
    let startedAt: Date
    let endedAt: Date

    var duration: TimeInterval {
        max(0, endedAt.timeIntervalSince(startedAt))
    }
}

enum TimingSessionState: String, Codable, Sendable {
    case running
    case paused
    case finished
}

@Model
final class TimingSession {
    @Attribute(.unique) var id: UUID
    var taskID: UUID
    var taskTitleSnapshot: String
    var goalIDSnapshot: UUID?
    var goalNameSnapshot: String?
    var startedAt: Date
    var endedAt: Date?
    var activeIntervalsData: Data
    var accumulatedSeconds: TimeInterval
    var runningStartedAt: Date?
    var stateRawValue: String

    init(
        id: UUID = UUID(),
        taskID: UUID,
        taskTitleSnapshot: String,
        goalIDSnapshot: UUID? = nil,
        goalNameSnapshot: String? = nil,
        startedAt: Date,
        endedAt: Date? = nil,
        activeIntervals: [TimingInterval] = [],
        accumulatedSeconds: TimeInterval = 0,
        runningStartedAt: Date? = nil,
        state: TimingSessionState
    ) {
        self.id = id
        self.taskID = taskID
        self.taskTitleSnapshot = taskTitleSnapshot
        self.goalIDSnapshot = goalIDSnapshot
        self.goalNameSnapshot = goalNameSnapshot
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.activeIntervalsData = (try? JSONEncoder().encode(activeIntervals)) ?? Data()
        self.accumulatedSeconds = accumulatedSeconds
        self.runningStartedAt = runningStartedAt
        self.stateRawValue = state.rawValue
    }

    var state: TimingSessionState {
        get { TimingSessionState(rawValue: stateRawValue) ?? .finished }
        set { stateRawValue = newValue.rawValue }
    }

    var activeIntervals: [TimingInterval] {
        get {
            guard !activeIntervalsData.isEmpty else { return [] }
            return (try? JSONDecoder().decode([TimingInterval].self, from: activeIntervalsData)) ?? []
        }
        set {
            activeIntervalsData = (try? JSONEncoder().encode(newValue)) ?? Data()
        }
    }
}
