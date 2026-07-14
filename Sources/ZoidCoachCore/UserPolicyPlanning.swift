import Foundation

public extension SchedulePolicy {
    func isWithinWorkWindow(at date: Date) -> Bool {
        guard let timeZone = TimeZone(identifier: timeZoneIdentifier) else { return false }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        guard let weekday = Weekday(rawValue: calendar.component(.weekday, from: date)) else { return false }
        let localTime = LocalTime(
            hour: calendar.component(.hour, from: date),
            minute: calendar.component(.minute, from: date)
        )
        return workWindows.contains { window in
            if window.end < window.start {
                if localTime >= window.start {
                    return window.weekdays.contains(weekday)
                }
                guard localTime <= window.end,
                      let previousDate = calendar.date(byAdding: .day, value: -1, to: date),
                      let previousWeekday = Weekday(rawValue: calendar.component(.weekday, from: previousDate))
                else { return false }
                return window.weekdays.contains(previousWeekday)
            }
            return window.weekdays.contains(weekday)
                && localTime >= window.start
                && localTime <= window.end
        }
    }

    func workIntervals(on day: Date) -> [CalendarInterval] {
        guard let timeZone = TimeZone(identifier: timeZoneIdentifier) else { return [] }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let startOfDay = calendar.startOfDay(for: day)
        guard let weekday = Weekday(rawValue: calendar.component(.weekday, from: day)) else { return [] }
        return workWindows.compactMap { window in
            guard window.weekdays.contains(weekday), window.start != window.end,
                  let start = calendar.date(bySettingHour: window.start.hour, minute: window.start.minute, second: 0, of: startOfDay)
            else { return nil }
            let endDay: Date
            if window.end < window.start {
                guard let nextDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) else { return nil }
                endDay = nextDay
            } else {
                endDay = startOfDay
            }
            guard let end = calendar.date(bySettingHour: window.end.hour, minute: window.end.minute, second: 0, of: endDay),
                  start < end
            else { return nil }
            return CalendarInterval(start: start, end: end)
        }
    }

    func planningCapacityMinutes(on day: Date, fixedCommitmentMinutes: Int = 0) -> Int {
        guard let timeZone = TimeZone(identifier: timeZoneIdentifier) else { return 0 }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        guard let weekday = Weekday(rawValue: calendar.component(.weekday, from: day)) else { return 0 }
        let configuredMinutes = workWindows
            .filter { $0.weekdays.contains(weekday) }
            .reduce(0) { total, window in
                let difference = window.end.minuteOfDay - window.start.minuteOfDay
                return total + (difference > 0 ? difference : difference < 0 ? difference + 24 * 60 : 0)
            }
        let flexibleMinutes = max(0, configuredMinutes - max(0, fixedCommitmentMinutes))
        return Int((Double(flexibleMinutes) * Double(planningCapacityPercent) / 100).rounded(.down))
    }
}
