import Foundation
import Testing
@testable import ZoidCoachCore
@testable import ZoidCoachInfrastructure

@Test
func scheduledReviewRemindersUseWorkdayAndWeekBoundariesWithoutDuplicates() throws {
    let databaseURL = temporaryReviewReminderDatabase("boundaries")
    defer { removeReviewReminderDatabase(databaseURL) }
    let now = try reviewReminderDate("2026-07-13T10:00:00Z")
    let outbox = try ActionOutboxStore(databaseURL: databaseURL, now: { now })
    let service = ReviewReminderService(outbox: outbox)
    let policy = reviewReminderPolicy(quietStart: LocalTime(hour: 16, minute: 0), quietEnd: LocalTime(hour: 18, minute: 0))

    let firstValue = try service.reconcile(policy: policy, policyVersion: 4, now: now)
    let replayValue = try service.reconcile(policy: policy, policyVersion: 4, now: now)
    let first = try #require(firstValue)
    let replay = try #require(replayValue)

    #expect(first.daily.wasInserted)
    #expect(first.weekly.wasInserted)
    #expect(replay.daily.wasInserted == false)
    #expect(replay.weekly.wasInserted == false)
    #expect(first.daily.command.id == replay.daily.command.id)
    #expect(first.weekly.command.id == replay.weekly.command.id)
    #expect(try outbox.recentCommands().count == 2)
    #expect(first.daily.command.entityID == "daily-review:2026-07-13")
    #expect(first.weekly.command.entityID == "weekly-review:2026-W29")

    guard case let .notification(daily) = first.daily.command.desiredState,
          case let .notification(weekly) = first.weekly.command.desiredState else {
        Issue.record("Expected review notification commands")
        return
    }
    #expect(daily.category == "DAILY_REVIEW")
    let expectedDaily = try reviewReminderDate("2026-07-13T18:00:00Z")
    let expectedWeekly = try reviewReminderDate("2026-07-17T18:00:00Z")
    #expect(daily.deliveryDate == expectedDaily)
    #expect(daily.body.contains("correct anything that looks wrong"))
    #expect(weekly.category == "WEEKLY_REVIEW")
    #expect(weekly.deliveryDate == expectedWeekly)
    #expect(weekly.body.contains("choose the next experiment"))
}

@Test
func scheduledReviewRemindersRollForwardAfterTheFinalWorkday() throws {
    let databaseURL = temporaryReviewReminderDatabase("roll-forward")
    defer { removeReviewReminderDatabase(databaseURL) }
    let now = try reviewReminderDate("2026-07-17T19:00:00Z")
    let outbox = try ActionOutboxStore(databaseURL: databaseURL, now: { now })
    let service = ReviewReminderService(outbox: outbox)

    let resultValue = try service.reconcile(
        policy: reviewReminderPolicy(),
        policyVersion: 5,
        now: now
    )
    let result = try #require(resultValue)

    #expect(result.daily.command.entityID == "daily-review:2026-07-20")
    #expect(result.weekly.command.entityID == "weekly-review:2026-W30")
    guard case let .notification(daily) = result.daily.command.desiredState,
          case let .notification(weekly) = result.weekly.command.desiredState else {
        Issue.record("Expected review notification commands")
        return
    }
    let expectedDaily = try reviewReminderDate("2026-07-20T17:00:00Z")
    let expectedWeekly = try reviewReminderDate("2026-07-24T17:00:00Z")
    #expect(daily.deliveryDate == expectedDaily)
    #expect(weekly.deliveryDate == expectedWeekly)
}

@Test
func scheduledReviewRemindersSupportOvernightWorkWindows() throws {
    let databaseURL = temporaryReviewReminderDatabase("overnight")
    defer { removeReviewReminderDatabase(databaseURL) }
    let now = try reviewReminderDate("2026-07-13T10:00:00Z")
    let outbox = try ActionOutboxStore(databaseURL: databaseURL, now: { now })
    let policy = reviewReminderPolicy(
        quietStart: LocalTime(hour: 3, minute: 0),
        quietEnd: LocalTime(hour: 4, minute: 0),
        workStart: LocalTime(hour: 20, minute: 0),
        workEnd: LocalTime(hour: 2, minute: 0)
    )

    let value = try ReviewReminderService(outbox: outbox).reconcile(
        policy: policy,
        policyVersion: 6,
        now: now
    )
    let result = try #require(value)
    guard case let .notification(daily) = result.daily.command.desiredState,
          case let .notification(weekly) = result.weekly.command.desiredState else {
        Issue.record("Expected review notification commands")
        return
    }

    #expect(result.daily.command.entityID == "daily-review:2026-07-13")
    #expect(result.weekly.command.entityID == "weekly-review:2026-W29")
    let expectedDaily = try reviewReminderDate("2026-07-14T02:00:00Z")
    let expectedWeekly = try reviewReminderDate("2026-07-18T02:00:00Z")
    #expect(daily.deliveryDate == expectedDaily)
    #expect(weekly.deliveryDate == expectedWeekly)
}

@Test
func observationModeStillSchedulesFactualReviewReminders() throws {
    let databaseURL = temporaryReviewReminderDatabase("observation-mode")
    defer { removeReviewReminderDatabase(databaseURL) }
    let now = try reviewReminderDate("2026-07-13T10:00:00Z")
    let policy = reviewReminderPolicy(mode: .observe)
    let policyStore = try PolicyStore(databaseURL: databaseURL, now: { now })
    _ = try policyStore.saveMutation(PolicyMutationRequest(
        requestID: "system-policy-v1:review-reminder-test:observation-mode",
        expectedVersion: 0,
        policy: policy,
        origin: .system(component: "review-reminder-test")
    ))
    let outbox = try ActionOutboxStore(databaseURL: databaseURL, now: { now })
    let resultValue = try ReviewReminderService(outbox: outbox).reconcile(
        policy: policy,
        policyVersion: 1,
        now: now
    )
    let result = try #require(resultValue)

    #expect(result.daily.command.state == .pending)
    #expect(result.weekly.command.state == .pending)
    let claimedValue = try outbox.claimNextReady()
    let claimed = try #require(claimedValue)
    let scheduledIDs = Set([result.daily.command.id, result.weekly.command.id])
    #expect(scheduledIDs.contains(claimed.id))
}

@Test
func scheduledReviewRemindersRequireAConfiguredFutureWorkday() throws {
    let databaseURL = temporaryReviewReminderDatabase("no-workday")
    defer { removeReviewReminderDatabase(databaseURL) }
    let now = try reviewReminderDate("2026-07-13T10:00:00Z")
    let outbox = try ActionOutboxStore(databaseURL: databaseURL, now: { now })
    let defaults = UserPolicy.defaults(timeZoneIdentifier: "UTC")
    let policy = UserPolicy(
        operatingMode: defaults.operatingMode,
        automationPause: defaults.automationPause,
        schedule: SchedulePolicy(
            timeZoneIdentifier: "UTC",
            workWindows: [],
            quietHours: defaults.schedule.quietHours,
            nightlyPlanningTime: defaults.schedule.nightlyPlanningTime,
            morningConfirmationTime: defaults.schedule.morningConfirmationTime,
            planningCapacityPercent: defaults.schedule.planningCapacityPercent
        ),
        calendar: defaults.calendar,
        privacy: defaults.privacy,
        wake: defaults.wake,
        behavior: defaults.behavior,
        capture: defaults.capture,
        gaming: defaults.gaming,
        reminderLists: defaults.reminderLists
    )

    #expect(try ReviewReminderService(outbox: outbox).reconcile(policy: policy, policyVersion: 1, now: now) == nil)
    #expect(try outbox.recentCommands().isEmpty)
}

private func reviewReminderPolicy(
    mode: OperatingMode = .suggest,
    quietStart: LocalTime = LocalTime(hour: 22, minute: 0),
    quietEnd: LocalTime = LocalTime(hour: 7, minute: 0),
    workStart: LocalTime = LocalTime(hour: 9, minute: 0),
    workEnd: LocalTime = LocalTime(hour: 17, minute: 0)
) -> UserPolicy {
    let defaults = UserPolicy.defaults(timeZoneIdentifier: "UTC")
    return UserPolicy(
        operatingMode: mode,
        automationPause: .running,
        schedule: SchedulePolicy(
            timeZoneIdentifier: "UTC",
            workWindows: [WeeklyWorkWindow(
                weekdays: [.monday, .tuesday, .wednesday, .thursday, .friday],
                start: workStart,
                end: workEnd
            )],
            quietHours: DailyTimeWindow(start: quietStart, end: quietEnd),
            nightlyPlanningTime: defaults.schedule.nightlyPlanningTime,
            morningConfirmationTime: defaults.schedule.morningConfirmationTime,
            planningCapacityPercent: defaults.schedule.planningCapacityPercent
        ),
        calendar: defaults.calendar,
        privacy: defaults.privacy,
        wake: defaults.wake,
        behavior: defaults.behavior,
        capture: defaults.capture,
        gaming: defaults.gaming,
        reminderLists: defaults.reminderLists
    )
}

private func reviewReminderDate(_ value: String) throws -> Date {
    try #require(ISO8601DateFormatter().date(from: value))
}

private func temporaryReviewReminderDatabase(_ label: String) -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("zoid-review-reminders-\(label)-\(UUID().uuidString).sqlite")
}

private func removeReviewReminderDatabase(_ url: URL) {
    for suffix in ["", "-wal", "-shm"] {
        try? FileManager.default.removeItem(atPath: url.path + suffix)
    }
}
