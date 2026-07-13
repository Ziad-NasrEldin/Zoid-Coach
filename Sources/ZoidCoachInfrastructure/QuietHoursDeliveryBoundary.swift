import Foundation
import ZoidCoachCore

public enum QuietHoursDeliveryBoundary {
    public static func nextAllowedDelivery(
        for proposedDate: Date,
        schedule: SchedulePolicy
    ) -> Date {
        guard let timeZone = TimeZone(identifier: schedule.timeZoneIdentifier) else {
            return proposedDate
        }
        let quietHours = schedule.quietHours
        guard quietHours.start != quietHours.end else { return proposedDate }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let minute = calendar.component(.hour, from: proposedDate) * 60
            + calendar.component(.minute, from: proposedDate)
        let start = quietHours.start.minuteOfDay
        let end = quietHours.end.minuteOfDay
        let isQuiet = quietHours.crossesMidnight
            ? minute >= start || minute < end
            : minute >= start && minute < end
        guard isQuiet else { return proposedDate }
        let match = DateComponents(hour: quietHours.end.hour, minute: quietHours.end.minute)
        return calendar.nextDate(
            after: proposedDate,
            matching: match,
            matchingPolicy: .nextTime,
            repeatedTimePolicy: .first,
            direction: .forward
        ) ?? proposedDate
    }
}
