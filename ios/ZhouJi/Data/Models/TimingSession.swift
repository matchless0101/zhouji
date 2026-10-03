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
    case invalid
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
    ) throws {
        self.id = id
        self.taskID = taskID
        self.taskTitleSnapshot = taskTitleSnapshot
        self.goalIDSnapshot = goalIDSnapshot
        self.goalNameSnapshot = goalNameSnapshot
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.activeIntervalsData = try Self.encodeIntervals(activeIntervals)
        self.accumulatedSeconds = accumulatedSeconds
        self.runningStartedAt = runningStartedAt
        self.stateRawValue = state.rawValue
    }

    var state: TimingSessionState {
        get { TimingSessionState(rawValue: stateRawValue) ?? .invalid }
        set { stateRawValue = newValue.rawValue }
    }

    var activeIntervals: [TimingInterval] {
        get throws {
            guard state != .invalid else { throw TimingDataError.invalidState }
            if activeIntervalsData.isEmpty { return [] } // Original empty interval representation.
            do {
                let intervals = try JSONDecoder().decode([TimingInterval].self, from: activeIntervalsData)
                try Self.validate(intervals)
                return intervals
            } catch { throw TimingDataError.invalidIntervals }
        }
    }

    func setActiveIntervals(_ intervals: [TimingInterval]) throws {
        activeIntervalsData = try Self.encodeIntervals(intervals)
    }

    private static func encodeIntervals(_ intervals: [TimingInterval]) throws -> Data {
        try validate(intervals)
        return try JSONEncoder().encode(intervals)
    }

    private static func validate(_ intervals: [TimingInterval]) throws {
        guard intervals.allSatisfy({
            $0.startedAt.timeIntervalSince1970.isFinite && $0.endedAt.timeIntervalSince1970.isFinite
                && $0.endedAt >= $0.startedAt
        }) else { throw TimingDataError.invalidIntervals }
    }
}

enum TimingDataError: LocalizedError {
    case invalidState, invalidIntervals
    var errorDescription: String? {
        switch self {
        case .invalidState: "保存的计时状态无法识别，原数据已保留，请先修复数据。"
        case .invalidIntervals: "保存的计时区间无法读取，原数据已保留，暂时无法统计或继续计时。"
        }
    }
}
