import Foundation
import Testing
@testable import ZoidCoachCore
@testable import ZoidCoachApp
@testable import ZoidCoachInfrastructure

@Test
func calendarScheduleReceiptRequiresTheExactCommittedPerTaskCommandSet() throws {
    let required: Set<AgentPlanCommandRequirement> = [
        .init(type: .reconcileCalendarBlock, entityID: "task-1"),
        .init(type: .scheduleNotification, entityID: "task-1"),
        .init(type: .setReminderPriority, entityID: "task-1"),
        .init(type: .setReminderDueDate, entityID: "task-1")
    ]
    let committed = required

    #expect(AgentMutationRouter.isCompleteScheduleCommandSet(required: required, committed: committed))
}

@Test
func sameSizedWrongCalendarScheduleCommandSetIsRejected() throws {
    let required: Set<AgentPlanCommandRequirement> = [
        .init(type: .reconcileCalendarBlock, entityID: "task-1"),
        .init(type: .scheduleNotification, entityID: "task-1"),
        .init(type: .setReminderPriority, entityID: "task-1"),
        .init(type: .setReminderDueDate, entityID: "task-1")
    ]
    let sameSizedWrong: Set<AgentPlanCommandRequirement> = [
        .init(type: .reconcileCalendarBlock, entityID: "task-1"),
        .init(type: .scheduleNotification, entityID: "task-1"),
        .init(type: .setReminderPriority, entityID: "task-1"),
        .init(type: .setReminderPriority, entityID: "task-2")
    ]

    #expect(!AgentMutationRouter.isCompleteScheduleCommandSet(required: required, committed: sameSizedWrong))
}

@Test
func incompleteCalendarScheduleCommandSetIsRejected() throws {
    let required: Set<AgentPlanCommandRequirement> = [
        .init(type: .reconcileCalendarBlock, entityID: "task-1"),
        .init(type: .scheduleNotification, entityID: "task-1")
    ]
    let incomplete: Set<AgentPlanCommandRequirement> = [
        .init(type: .reconcileCalendarBlock, entityID: "task-1")
    ]

    #expect(!AgentMutationRouter.isCompleteScheduleCommandSet(required: required, committed: incomplete))
}

@Test
func ambiguousCalendarReplyRestoresAsReconcilingInsteadOfNothingWritten() throws {
    var state = CalendarPlanApprovalState()
    state.begin(
        entries: [DailyPlanEntry(reminderID: "task-1", rank: 1, isMainObjective: true, estimateMinutes: 30)],
        titlesByReminderID: ["task-1": "Write proposal"],
        availableMinutes: 120,
        fixedCommitmentMinutes: 30,
        usesCalendarAvailability: true
    )
    state.markReconciling(approvedAt: Date(timeIntervalSince1970: 1_752_489_600))
    let receipt = try #require(state.receipt)

    var relaunched = CalendarPlanApprovalState()
    relaunched.restore(receipt)

    #expect(relaunched.writeState == .reconciling)
    #expect(relaunched.receipt?.summary.contains("may already be queued") == true)
    #expect(relaunched.receipt?.summary.contains("Nothing was written") == false)
}

@Test
func durableCalendarOperationReplaysExactReceiptWithoutRecomputingChangedInputs() async throws {
    let databaseURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("zoid-calendar-router-\(UUID().uuidString).sqlite")
    defer { removeCalendarRouterDatabase(databaseURL) }
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone.current
    let day = try #require(calendar.date(from: DateComponents(year: 2026, month: 7, day: 14)))
    let now = try #require(calendar.date(bySettingHour: 8, minute: 0, second: 0, of: day))
    let plans = try AutonomousPlanStore(databaseURL: databaseURL)
    try plans.replaceDailyPlan(
        DailyPlanProposal(
            items: [
                PlannedTask(
                    taskID: "task-1",
                    title: "Original reviewed task",
                    rank: 1,
                    estimateMinutes: 30,
                    reason: "Reviewed",
                    score: 100
                )
            ],
            mainObjectiveTaskID: "task-1",
            plannedFocusMinutes: 30,
            availableFocusMinutes: 300
        ),
        for: day
    )
    let reminders = try ReminderSnapshotStore(databaseURL: databaseURL)
    try reminders.replace([
        ReminderSourceSnapshot(
            id: "task-1",
            title: "Original reviewed task",
            dueDate: nil,
            priority: 0
        )
    ])
    let outbox = try ActionOutboxStore(databaseURL: databaseURL)
    let operations = try CalendarPlanOperationStore(databaseURL: databaseURL)
    let router = AgentMutationRouter(
        outbox: outbox,
        stateStore: try AgentOwnedStateStore(databaseURL: databaseURL),
        taskHistory: try TaskHistoryStore(databaseURL: databaseURL),
        meetingArchive: try ScreenwatchArchive(databaseURL: databaseURL),
        planScheduler: AgentPlanScheduler(
            plans: plans,
            reminders: reminders,
            outbox: outbox,
            calendar: EmptyCalendarRouterSource(),
            now: { now }
        ),
        calendarPlanOperations: operations,
        policyStore: try PolicyStore(databaseURL: databaseURL),
        reminderSnapshots: reminders,
        privacyData: try PrivacyDataService(databaseURL: databaseURL)
    )
    let operationID = UUID()

    let first = try await router.apply(.schedulePlan(day: day, operationID: operationID))
    #expect(first.accepted)
    #expect(!first.commandIDs.isEmpty)
    try reminders.replace([
        ReminderSourceSnapshot(
            id: "task-1",
            title: "Changed after the reply was lost",
            dueDate: day,
            priority: 9
        )
    ])

    let replay = try await router.apply(.schedulePlan(day: day, operationID: operationID))
    #expect(replay == first)
    #expect(try operations.load(id: operationID)?.state == .completed)
    #expect(Set(try outbox.recentCommands(limit: 20).map(\.id)) == Set(first.commandIDs))

    await #expect(throws: CalendarPlanOperationStoreError.operationKeyConflict) {
        _ = try await router.apply(
            .schedulePlan(day: day.addingTimeInterval(86_400), operationID: operationID)
        )
    }
}

private struct EmptyCalendarRouterSource: CalendarAvailabilitySource {
    func commitments(
        from start: Date,
        through end: Date,
        calendarIdentifiers: [String]
    ) async throws -> [ZoidCoachCore.CalendarCommitment] {
        []
    }
}

private func removeCalendarRouterDatabase(_ url: URL) {
    for suffix in ["", "-wal", "-shm"] {
        try? FileManager.default.removeItem(atPath: url.path + suffix)
    }
}
