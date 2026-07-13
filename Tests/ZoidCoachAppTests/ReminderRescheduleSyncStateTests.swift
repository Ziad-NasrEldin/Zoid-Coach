import Foundation
import Testing
@testable import ZoidCoachCore
@testable import ZoidCoachInfrastructure

@Test
func reminderRescheduleSyncDistinguishesPendingFailureAndConfirmation() {
    let dueDate = Date(timeIntervalSince1970: 1_800_086_400)
    let pending = ReminderRescheduleSyncState(
        taskID: "focus",
        taskTitle: "Finish proposal",
        dueDate: dueDate,
        audit: [rescheduleAudit(state: "pending", attempts: 0)]
    )
    let failed = ReminderRescheduleSyncState(
        taskID: "focus",
        taskTitle: "Finish proposal",
        dueDate: dueDate,
        audit: [rescheduleAudit(state: "retryable_failure", attempts: 1)]
    )
    let confirmed = ReminderRescheduleSyncState(
        taskID: "focus",
        taskTitle: "Finish proposal",
        dueDate: dueDate,
        audit: [rescheduleAudit(state: "succeeded", attempts: 2)]
    )

    #expect(pending.phase == .pending)
    #expect(pending.userFacingDetail.contains("saved locally"))
    #expect(failed.phase == .failed)
    #expect(failed.userFacingDetail.contains("rejected"))
    #expect(failed.userFacingDetail.contains("task history are safe"))
    #expect(confirmed.phase == .confirmed)
    #expect(confirmed.userFacingDetail.contains("confirmed by Apple Reminders"))
}

@Test
func reminderRescheduleSyncIgnoresCompletionAndOtherTaskCommands() {
    let dueDate = Date(timeIntervalSince1970: 1_800_086_400)
    let state = ReminderRescheduleSyncState(
        taskID: "focus",
        taskTitle: "Finish proposal",
        dueDate: dueDate,
        audit: [
            ActionAuditEntry(
                id: "completion",
                actionType: ActionCommandType.completeReminder.rawValue,
                entityID: "focus",
                state: "retryable_failure",
                attemptCount: 1,
                createdAt: dueDate,
                updatedAt: dueDate,
                canUndo: false
            ),
            ActionAuditEntry(
                id: "other-task",
                actionType: ActionCommandType.setReminderDueDate.rawValue,
                entityID: "other",
                state: "retryable_failure",
                attemptCount: 1,
                createdAt: dueDate,
                updatedAt: dueDate,
                canUndo: false
            ),
        ]
    )

    #expect(state.phase == .notRequested)
    #expect(!state.isVisible)
}

@Test
func explicitRescheduleMutationQueuesOneSupersedingReminderDueDateCommand() async throws {
    let databaseURL = temporaryRescheduleDatabaseURL()
    defer { removeRescheduleDatabase(at: databaseURL) }
    let reminders = try ReminderSnapshotStore(databaseURL: databaseURL)
    _ = try reminders.synchronize([
        ReminderSourceSnapshot(
            id: "focus",
            title: "Finish proposal",
            dueDate: nil,
            priority: 5
        )
    ])
    let outbox = try ActionOutboxStore(databaseURL: databaseURL)
    let policyStore = try PolicyStore(databaseURL: databaseURL)
    _ = try policyStore.save(.defaults(timeZoneIdentifier: "Africa/Cairo"))
    let router = try makeRescheduleRouter(
        databaseURL: databaseURL,
        reminders: reminders,
        outbox: outbox,
        policyStore: policyStore
    )
    let firstDate = Date().addingTimeInterval(24 * 60 * 60)
    let secondDate = firstDate.addingTimeInterval(24 * 60 * 60)

    let first = try await router.apply(.rescheduleReminder(reminderID: "focus", dueDate: firstDate))
    let second = try await router.apply(.rescheduleReminder(reminderID: "focus", dueDate: secondDate))

    #expect(first.commandIDs.count == 1)
    #expect(second.commandIDs.count == 1)
    #expect(first.commandIDs != second.commandIDs)
    let latest = try #require(try outbox.latestCommand(type: .setReminderDueDate, entityID: "focus"))
    #expect(latest.id == second.commandIDs.first)
    guard case let .reminder(desired) = latest.desiredState else {
        Issue.record("Expected a Reminder due-date desired state")
        return
    }
    let persistedDueDate = try #require(desired.dueDate)
    #expect(abs(persistedDueDate.timeIntervalSince(secondDate)) < 1)
}

@Test
func fullyDeferredDailyPlanPersistsWithoutInventingAnActiveMainObjective() throws {
    let databaseURL = temporaryRescheduleDatabaseURL()
    defer { removeRescheduleDatabase(at: databaseURL) }
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let deferredUntil = now.addingTimeInterval(24 * 60 * 60)
    let stateStore = try AgentOwnedStateStore(databaseURL: databaseURL)

    try stateStore.replaceDailyPlan([
        AgentPlanItem(
            reminderID: "focus",
            rank: 1,
            isMainObjective: false,
            estimateMinutes: 45,
            selectionReason: "Deferred from coaching",
            selectionScore: 100,
            deferredUntil: deferredUntil
        )
    ], day: now, now: now)

    let persisted = try AutonomousPlanStore(databaseURL: databaseURL).loadDailyPlan(for: now)
    let item = try #require(persisted.first)
    #expect(!item.isMainObjective)
    #expect(abs(try #require(item.deferredUntil).timeIntervalSince(deferredUntil)) < 1)
}

private func rescheduleAudit(state: String, attempts: Int) -> ActionAuditEntry {
    let date = Date(timeIntervalSince1970: 1_800_000_000 + TimeInterval(attempts))
    return ActionAuditEntry(
        id: "reschedule-\(attempts)",
        actionType: ActionCommandType.setReminderDueDate.rawValue,
        entityID: "focus",
        state: state,
        attemptCount: attempts,
        createdAt: date,
        updatedAt: date,
        canUndo: false
    )
}

private struct EmptyRescheduleCalendar: CalendarAvailabilitySource {
    func commitments(
        from start: Date,
        through end: Date,
        calendarIdentifiers: [String]
    ) async throws -> [ZoidCoachCore.CalendarCommitment] {
        []
    }
}

private func makeRescheduleRouter(
    databaseURL: URL,
    reminders: ReminderSnapshotStore,
    outbox: ActionOutboxStore,
    policyStore: PolicyStore
) throws -> AgentMutationRouter {
    AgentMutationRouter(
        outbox: outbox,
        stateStore: try AgentOwnedStateStore(databaseURL: databaseURL),
        taskHistory: try TaskHistoryStore(databaseURL: databaseURL),
        meetingArchive: try ScreenwatchArchive(databaseURL: databaseURL),
        planScheduler: AgentPlanScheduler(
            plans: try AutonomousPlanStore(databaseURL: databaseURL),
            reminders: reminders,
            outbox: outbox,
            calendar: EmptyRescheduleCalendar()
        ),
        policyStore: policyStore,
        reminderSnapshots: reminders,
        privacyData: try PrivacyDataService(databaseURL: databaseURL)
    )
}

private func temporaryRescheduleDatabaseURL() -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("zoid-reschedule-sync-\(UUID().uuidString).sqlite")
}

private func removeRescheduleDatabase(at url: URL) {
    for suffix in ["", "-wal", "-shm"] {
        try? FileManager.default.removeItem(atPath: url.path + suffix)
    }
}
