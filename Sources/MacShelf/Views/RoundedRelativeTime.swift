import Foundation

enum RoundedRelativeTime {
    static func string(for date: Date, relativeTo now: Date = .now) -> String {
        let elapsed = max(0, Int(now.timeIntervalSince(date)))

        if elapsed < 60 {
            return "now"
        }
        if elapsed < 3_600 {
            return "\(max(1, elapsed / 60)) min ago"
        }
        if elapsed < 86_400 {
            return "\(max(1, elapsed / 3_600)) h ago"
        }
        if elapsed < 604_800 {
            return "\(max(1, elapsed / 86_400)) d ago"
        }
        return "\(max(1, elapsed / 604_800)) wk ago"
    }
}
