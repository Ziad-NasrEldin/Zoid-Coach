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
    let scheduler = AgentPlanScheduler(
        plans: planStore,
        reminders: reminders,
        outbox: outbox,
        calendar: SchedulerCalendar(commitments: [fixed]),
        now: { fixedStart.addingTimeInterval(-60 * 60) }
    )
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
    #expect(Set(result.commandIDs) == Set(commands.map(\.id)))
    if case let .calendarBlock(desired) = block.desiredState {
        #expect(desired.start >= fixed.end)
    } else {
        Issue.record("Expected calendar block desired state")
    }
    #expect(commands.contains { $0.type == .setReminderPriority })
    #expect(commands.contains { $0.type == .setReminderDueDate })
}

@Test
func daytimeReplanPreservesPastAndActiveOwnedBlocks() async throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("zoid-plan-scheduler-daytime-\(UUID().uuidString).sqlite")
    defer { removePlanSchedulerDatabase(url) }
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    let day = calendar.date(from: DateComponents(year: 2026, month: 7, day: 6))!
    let now = calendar.date(bySettingHour: 11, minute: 0, second: 0, of: day)!
    let planStore = try AutonomousPlanStore(databaseURL: url)
    try planStore.replaceDailyPlan(
        DailyPlanProposal(
            items: [
                PlannedTask(taskID: "active", title: "Already active", rank: 1, estimateMinutes: 60, reason: "Started", score: 900),
                PlannedTask(taskID: "next", title: "Next", rank: 2, estimateMinutes: 60, reason: "Ready", score: 800),
            ],
            mainObjectiveTaskID: "active",
            plannedFocusMinutes: 120,
            availableFocusMinutes: 300
        ),
        for: day
    )
    let reminders = try ReminderSnapshotStore(databaseURL: url)
    try reminders.replace([
        ReminderSourceSnapshot(id: "active", title: "Already active", dueDate: nil, priority: 0),
        ReminderSourceSnapshot(id: "next", title: "Next", dueDate: nil, priority: 0),
    ])
    let dayKey = "2026-07-06"
    let commitments = [
        CalendarCommitment(
            id: "past-event",
            title: "Past",
            start: calendar.date(bySettingHour: 9, minute: 0, second: 0, of: day)!,
            end: calendar.date(bySettingHour: 10, minute: 0, second: 0, of: day)!,
            calendarIdentifier: "work",
            ownershipToken: "zoid-plan:\(dayKey):past"
        ),
        CalendarCommitment(
            id: "active-event",
            title: "Already active",
            start: calendar.date(bySettingHour: 10, minute: 30, second: 0, of: day)!,
            end: calendar.date(bySettingHour: 11, minute: 30, second: 0, of: day)!,
            calendarIdentifier: "work",
            ownershipToken: "zoid-plan:\(dayKey):active"
        ),
        CalendarCommitment(
            id: "obsolete-future",
            title: "Obsolete",
            start: calendar.date(bySettingHour: 15, minute: 0, second: 0, of: day)!,
            end: calendar.date(bySettingHour: 16, minute: 0, second: 0, of: day)!,
            calendarIdentifier: "work",
            ownershipToken: "zoid-plan:\(dayKey):obsolete"
        ),
    ]
    let outbox = try ActionOutboxStore(databaseURL: url, now: { now })
    let staleActiveReconcile = try outbox.enqueue(
        type: .reconcileCalendarBlock,
        entityID: "active",
        desiredState: .calendarBlock(CalendarBlockDesiredState(
            title: "Already active",
            start: calendar.date(bySettingHour: 14, minute: 0, second: 0, of: day)!,
            end: calendar.date(bySettingHour: 15, minute: 0, second: 0, of: day)!,
            ownershipToken: "zoid-plan:\(dayKey):active",
            planItemID: "active"
        )),
        planVersion: 1
    ).command
    let stalePastDeletion = try outbox.enqueue(
        type: .deleteCalendarBlock,
        entityID: "past-event",
        desiredState: .deleteOwnedCalendarBlock(ownershipToken: "zoid-plan:\(dayKey):past"),
        planVersion: 1
    ).command
    let scheduler = AgentPlanScheduler(
        plans: planStore,
        reminders: reminders,
        outbox: outbox,
        calendar: SchedulerCalendar(commitments: commitments),
        now: { now }
    )
    var policy = UserPolicy.defaults(timeZoneIdentifier: "UTC")
    policy = UserPolicy(
        operatingMode: policy.operatingMode,
        automationPause: policy.automationPause,
        schedule: policy.schedule,
        calendar: CalendarSelectionPolicy(visibleCalendarIdentifiers: ["work"], schedulingCalendarIdentifier: nil),
        privacy: policy.privacy,
        wake: policy.wake
    )

    _ = try await scheduler.enqueueSchedule(for: day, policy: policy, policyVersion: 2)
    let commands = try outbox.recentCommands(limit: 30)
    let calendarCommands = commands.filter {
        ($0.type == .reconcileCalendarBlock || $0.type == .deleteCalendarBlock) && $0.state != .cancelled
    }

    #expect(try outbox.command(commandID: staleActiveReconcile.id)?.state == .cancelled)
    #expect(try outbox.command(commandID: stalePastDeletion.id)?.state == .cancelled)
    #expect(calendarCommands.contains { $0.type == .deleteCalendarBlock && $0.entityID == "obsolete-future" })
    #expect(calendarCommands.contains { $0.type == .deleteCalendarBlock && $0.entityID == "past-event" } == false)
    #expect(calendarCommands.contains { $0.type == .reconcileCalendarBlock && $0.entityID == "active" } == false)
    let nextCommand = try #require(calendarCommands.first { $0.type == .reconcileCalendarBlock && $0.entityID == "next" })
    if case let .calendarBlock(desired) = nextCommand.desiredState {
        #expect(desired.start >= commitments[1].end)
        #expect(desired.start >= now)
    } else {
        Issue.record("Expected a calendar block desired state")
    }
}

@Test
func agentSchedulerDoesNotPartiallyWriteWhenEveryReviewedTaskCannotFit() async throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("zoid-plan-scheduler-atomic-\(UUID().uuidString).sqlite")
    defer { removePlanSchedulerDatabase(url) }
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    let day = calendar.date(from: DateComponents(year: 2026, month: 7, day: 6))!
    let planStore = try AutonomousPlanStore(databaseURL: url)
    try planStore.replaceDailyPlan(
        DailyPlanProposal(
            items: [
                PlannedTask(taskID: "first", title: "First", rank: 1, estimateMinutes: 600, reason: "Priority", score: 900),
                PlannedTask(taskID: "second", title: "Second", rank: 2, estimateMinutes: 600, reason: "Priority", score: 800)
            ],
            mainObjectiveTaskID: "first",
            plannedFocusMinutes: 1_200,
            availableFocusMinutes: 1_200
        ),
        for: day
    )
    let reminders = try ReminderSnapshotStore(databaseURL: url)
    try reminders.replace([
        ReminderSourceSnapshot(id: "first", title: "First", dueDate: nil, priority: 0),
        ReminderSourceSnapshot(id: "second", title: "Second", dueDate: nil, priority: 0)
    ])
    let outbox = try ActionOutboxStore(databaseURL: url)
    let workStart = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: day)!
    let commitments = [
        CalendarCommitment(
            id: "fragment",
            title: "Fixed",
            start: workStart.addingTimeInterval(90 * 60),
            end: workStart.addingTimeInterval(150 * 60),
            calendarIdentifier: "work"
        )
    ]
    let scheduler = AgentPlanScheduler(
        plans: planStore,
        reminders: reminders,
        outbox: outbox,
        calendar: SchedulerCalendar(commitments: commitments),
        now: { workStart.addingTimeInterval(-60 * 60) }
    )
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

    #expect(!result.unscheduledTaskIDs.isEmpty)
    #expect(result.commandIDs.isEmpty)
    #expect(try outbox.recentCommands(limit: 20).isEmpty)
}

private struct SchedulerCalendar: CalendarAvailabilitySource {
    let commitments: [CalendarCommitment]
    func commitments(from start: Date, through end: Date, calendarIdentifiers: [String]) async throws -> [CalendarCommitment] { commitments }
}

private func removePlanSchedulerDatabase(_ url: URL) {
    for suffix in ["", "-wal", "-shm"] { try? FileManager.default.removeItem(atPath: url.path + suffix) }
}
