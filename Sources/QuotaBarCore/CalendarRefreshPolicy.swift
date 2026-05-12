import Foundation

public enum CalendarRefreshPolicy {
    public static func secondsUntilNextDay(
        from now: Date,
        calendar: Calendar = .current
    ) -> TimeInterval {
        let startOfToday = calendar.startOfDay(for: now)
        let nextDay = calendar.date(byAdding: .day, value: 1, to: startOfToday) ?? now.addingTimeInterval(86_400)
        return max(1, nextDay.timeIntervalSince(now))
    }
}
