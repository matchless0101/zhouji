import Foundation

enum ElapsedTimeText {
    static func string(for value: TimeInterval) -> String {
        let seconds = max(0, Int(value.rounded(.down)))
        let hours = seconds / 3_600
        let minutes = (seconds % 3_600) / 60

        if hours > 0, minutes > 0 {
            return "\(hours)小时\(minutes)分"
        }
        if hours > 0 {
            return "\(hours)小时"
        }
        if minutes > 0 {
            return "\(minutes)分钟"
        }
        return seconds > 0 ? "\(seconds)秒" : "0分钟"
    }
}
