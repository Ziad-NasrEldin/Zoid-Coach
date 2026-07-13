import Foundation
import Testing
import ZoidCoachCore
@testable import ZoidCoachInfrastructure

@Suite("Quiet hours delivery boundary")
struct QuietHoursDeliveryBoundaryTests {
    @Test("overnight quiet hours defer both sides of midnight to the same boundary")
    func overnightWindow() throws {
        let schedule = schedule(quietStart: (22, 30), quietEnd: (7, 15))
        let lateEvening = try date("2026-07-13T23:45:00+03:00")
        let earlyMorning = try date("2026-07-14T06:30:00+03:00")
        let expected = try date("2026-07-14T07:15:00+03:00")

        #expect(QuietHoursDeliveryBoundary.nextAllowedDelivery(for: lateEvening, schedule: schedule) == expected)
        #expect(QuietHoursDeliveryBoundary.nextAllowedDelivery(for: earlyMorning, schedule: schedule) == expected)
    }

    @Test("same-day quiet hours defer to their end")
    func sameDayWindow() throws {
        let schedule = schedule(quietStart: (12, 0), quietEnd: (14, 30))
        let proposed = try date("2026-07-13T13:15:00+03:00")
        let expected = try date("2026-07-13T14:30:00+03:00")

        #expect(QuietHoursDeliveryBoundary.nextAllowedDelivery(for: proposed, schedule: schedule) == expected)
    }

    @Test("delivery outside quiet hours stays immediate including the exact end")
    func outsideWindow() throws {
        let schedule = schedule(quietStart: (22, 30), quietEnd: (7, 15))
        let daytime = try date("2026-07-13T15:00:00+03:00")
        let exactEnd = try date("2026-07-13T07:15:00+03:00")

        #expect(QuietHoursDeliveryBoundary.nextAllowedDelivery(for: daytime, schedule: schedule) == daytime)
        #expect(QuietHoursDeliveryBoundary.nextAllowedDelivery(for: exactEnd, schedule: schedule) == exactEnd)
    }

    @Test("the current persisted boundary can change without recreating the coordinator closure")
    func changedPolicyIsReadForEveryDelivery() throws {
        var current = schedule(quietStart: (22, 0), quietEnd: (7, 0))
        let boundary: (Date) -> Date = { proposed in
            QuietHoursDeliveryBoundary.nextAllowedDelivery(for: proposed, schedule: current)
        }
        let proposed = try date("2026-07-13T21:30:00+03:00")
        #expect(boundary(proposed) == proposed)

        current = schedule(quietStart: (21, 0), quietEnd: (6, 30))
        let changedExpected = try date("2026-07-14T06:30:00+03:00")
        #expect(boundary(proposed) == changedExpected)
    }

    private func schedule(
        quietStart: (Int, Int),
        quietEnd: (Int, Int)
    ) -> SchedulePolicy {
        let defaults = UserPolicy.defaults(timeZoneIdentifier: "Africa/Cairo").schedule
        return SchedulePolicy(
            timeZoneIdentifier: defaults.timeZoneIdentifier,
            workWindows: defaults.workWindows,
            quietHours: DailyTimeWindow(
                start: LocalTime(hour: quietStart.0, minute: quietStart.1),
                end: LocalTime(hour: quietEnd.0, minute: quietEnd.1)
            ),
            nightlyPlanningTime: defaults.nightlyPlanningTime,
            morningConfirmationTime: defaults.morningConfirmationTime,
            planningCapacityPercent: defaults.planningCapacityPercent
        )
    }

    private func date(_ value: String) throws -> Date {
        try #require(ISO8601DateFormatter().date(from: value))
    }
}
