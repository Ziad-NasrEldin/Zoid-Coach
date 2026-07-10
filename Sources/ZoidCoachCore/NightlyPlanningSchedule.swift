import Foundation

public struct NightlyPlanningSchedule: Sendable {
    private let hour: Int
    private let minute: Int
    private let calendar: Calendar

    public init(hour: Int = 22, minute: Int = 30, calendar: Calendar = .current) {
        self.hour = min(max(hour, 0), 23)
        self.minute = min(max(minute, 0), 59)
        self.calendar = calendar
    }

    public func targetDay(for now: Date) -> Date? {
        let startOfToday = calendar.startOfDay(for: now)
        guard let trigger = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: startOfToday),
              now >= trigger
        else { return nil }
        return calendar.date(byAdding: .day, value: 1, to: startOfToday)
    }
}
