import Foundation
import ZoidCoachCore

public struct ReviewReminderReconciliation: Equatable, Sendable {
    public let daily: ActionEnqueueResult
    public let weekly: ActionEnqueueResult

    public init(daily: ActionEnqueueResult, weekly: ActionEnqueueResult) {
        self.daily = daily
        self.weekly = weekly
    }
}

public final class ReviewReminderService: @unchecked Sendable {
    private struct Occurrence {
        let key: String
        let deliveryDate: Date
    }

    private let outbox: ActionOutboxStore

    public init(outbox: ActionOutboxStore) {
        self.outbox = outbox
    }

    public func reconcile(
        policy: UserPolicy,
        policyVersion: Int,
        now: Date = Date()
    ) throws -> ReviewReminderReconciliation? {
        guard let daily = nextDailyOccurrence(after: now, schedule: policy.schedule),
              let weekly = nextWeeklyOccurrence(after: now, schedule: policy.schedule)
        else { return nil }
        let dailyDelivery = QuietHoursDeliveryBoundary.nextAllowedDelivery(
            for: daily.deliveryDate,
            schedule: policy.schedule
        )
        let weeklyDelivery = QuietHoursDeliveryBoundary.nextAllowedDelivery(
            for: weekly.deliveryDate,
            schedule: policy.schedule
        )
        let dailyID = "daily-review:\(daily.key)"
        let weeklyID = "weekly-review:\(weekly.key)"
        let dailyResult = try outbox.enqueue(
            type: .scheduleNotification,
            entityID: dailyID,
            desiredState: .notification(NotificationDesiredState(
                category: "DAILY_REVIEW",
                title: "Today is ready to review",
                body: "Open Reviews to check observed activity, correct anything that looks wrong, and close the day.",
                promptID: dailyID,
                deliveryDate: dailyDelivery
            )),
            planVersion: policyVersion,
            supersedingPending: true,
            origin: .scheduledReview
        )
        let weeklyResult = try outbox.enqueue(
            type: .scheduleNotification,
            entityID: weeklyID,
            desiredState: .notification(NotificationDesiredState(
                category: "WEEKLY_REVIEW",
                title: "Your weekly review is ready",
                body: "Open Reviews to inspect the evidence, correct anything that looks wrong, and choose the next experiment.",
                promptID: weeklyID,
                deliveryDate: weeklyDelivery
            )),
            planVersion: policyVersion,
            supersedingPending: true,
            origin: .scheduledReview
        )
        return ReviewReminderReconciliation(daily: dailyResult, weekly: weeklyResult)
    }

    private func nextDailyOccurrence(after date: Date, schedule: SchedulePolicy) -> Occurrence? {
        let calendar = localCalendar(schedule: schedule)
        let startOfToday = calendar.startOfDay(for: date)
        for offset in 0..<8 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: startOfToday),
                  let review = dailyReview(on: day, schedule: schedule, calendar: calendar),
                  review > date
            else { continue }
            return Occurrence(key: localDay(day, calendar: calendar), deliveryDate: review)
        }
        return nil
    }

    private func dailyReview(
        on day: Date,
        schedule: SchedulePolicy,
        calendar: Calendar
    ) -> Date? {
        guard let reviewTime = schedule.dailyReviewTime else {
            return workdayEnd(on: day, schedule: schedule, calendar: calendar)
        }
        guard let weekday = Weekday(rawValue: calendar.component(.weekday, from: day)),
              schedule.workWindows.contains(where: { $0.weekdays.contains(weekday) })
        else { return nil }
        return calendar.date(
            bySettingHour: reviewTime.hour,
            minute: reviewTime.minute,
            second: 0,
            of: calendar.startOfDay(for: day)
        )
    }

    private func nextWeeklyOccurrence(after date: Date, schedule: SchedulePolicy) -> Occurrence? {
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = TimeZone(identifier: schedule.timeZoneIdentifier) ?? .current
        guard let currentWeekStart = calendar.dateInterval(of: .weekOfYear, for: date)?.start else {
            return nil
        }
        for weekOffset in 0..<2 {
            guard let weekStart = calendar.date(byAdding: .weekOfYear, value: weekOffset, to: currentWeekStart) else {
                continue
            }
            let ends = (0..<7).compactMap { dayOffset -> Date? in
                guard let day = calendar.date(byAdding: .day, value: dayOffset, to: weekStart) else { return nil }
                return workdayEnd(on: day, schedule: schedule, calendar: calendar)
            }
            guard let end = ends.max(), end > date else { continue }
            let components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: weekStart)
            let key = String(format: "%04d-W%02d", components.yearForWeekOfYear ?? 0, components.weekOfYear ?? 0)
            return Occurrence(key: key, deliveryDate: end)
        }
        return nil
    }

    private func workdayEnd(
        on day: Date,
        schedule: SchedulePolicy,
        calendar: Calendar
    ) -> Date? {
        let startOfDay = calendar.startOfDay(for: day)
        guard let weekday = Weekday(rawValue: calendar.component(.weekday, from: day)) else { return nil }
        return schedule.workWindows.filter { $0.weekdays.contains(weekday) }.compactMap { window in
            guard let endOnStartDay = calendar.date(
                bySettingHour: window.end.hour,
                minute: window.end.minute,
                second: 0,
                of: startOfDay
            ) else { return nil }
            if window.end <= window.start {
                return calendar.date(byAdding: .day, value: 1, to: endOnStartDay)
            }
            return endOnStartDay
        }.max()
    }

    private func localCalendar(schedule: SchedulePolicy) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: schedule.timeZoneIdentifier) ?? .current
        return calendar
    }

    private func localDay(_ date: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
    }
}
