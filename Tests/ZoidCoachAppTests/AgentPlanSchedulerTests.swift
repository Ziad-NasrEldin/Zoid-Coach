import Foundation
import Testing
@testable import ZoidCoachCore
@testable import ZoidCoachInfrastructure

@Test
func agentSchedulerConstrainsBlocksByFixedCalendarAndEnqueuesReminderMutations() async throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("zoid-plan-scheduler-\(UUID().uuidString).sqlite")
    defer { removePlanSchedulerDatabase(url) }
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    let day = calendar.date(from: DateComponents(year: 2026, month: 7, day: 6))!
    let planStore = try AutonomousPlanStore(databaseURL: url)
    try planStore.replaceDailyPlan(
        DailyPlanProposal(
            items: [PlannedTask(taskID: "urgent", title: "Urgent", rank: 1, estimateMinutes: 60, reason: "Due", score: 900)],
            mainObjectiveTaskID: "urgent",
            plannedFocusMinutes: 60,
            availableFocusMinutes: 300
        ),
        for: day
    )
    let reminders = try ReminderSnapshotStore(databaseURL: url)
    try reminders.replace([ReminderSourceSnapshot(id: "urgent", title: "Urgent", dueDate: nil, priority: 0)])
    let fixedStart = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: day)!
    let fixed = CalendarCommitment(id: "fixed", title: "Meeting", start: fixedStart, end: fixedStart.addingTimeInterval(60 * 60), calendarIdentifier: "work")
    let outbox = try ActionOutboxStore(databaseURL: url)
    let scheduler = AgentPlanScheduler(plans: planStore, reminders: reminders, outbox: outbox, calendar: SchedulerCalendar(commitments: [fixed]))
    var policy = UserPolicy.defaults(timeZoneIdentifier: "UTC")
    policy = UserPolicy(
        operatingMode: policy.operatingMode,
        automationPause: policy.automationPause,
        schedule: policy.schedule,
        calendar: CalendarSelectionPolicy(visibleCalendarIdentifiers: ["work"], schedulingCalendarIdentifier: nil),
        privacy: policy.privacy,
        wake: policy.wake
    )

    let result = try await scheduler.enqueueSchedule(for: day, policy: policy, policyVersion: 1)
    let commands = try outbox.recentCommands(limit: 20)
    let block = try #require(commands.first(where: { $0.type == .reconcileCalendarBlock }))

    #expect(result.scheduledBlockCount == 1)
    #expect(result.reminderMutationCount == 2)
    if case let .calendarBlock(desired) = block.desiredState {
        #expect(desired.start >= fixed.end)
    } else {
        Issue.record("Expected calendar block desired state")
    }
    #expect(commands.contains { $0.type == .setReminderPriority })
    #expect(commands.contains { $0.type == .setReminderDueDate })
}

private struct SchedulerCalendar: CalendarAvailabilitySource {
    let commitments: [CalendarCommitment]
    func commitments(from start: Date, through end: Date, calendarIdentifiers: [String]) async throws -> [CalendarCommitment] { commitments }
}

private func removePlanSchedulerDatabase(_ url: URL) {
    for suffix in ["", "-wal", "-shm"] { try? FileManager.default.removeItem(atPath: url.path + suffix) }
}
