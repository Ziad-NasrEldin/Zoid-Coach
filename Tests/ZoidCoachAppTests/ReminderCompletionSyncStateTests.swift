import Foundation
import Testing
@testable import ZoidCoachCore

@Test
func reminderCompletionSyncUsesLatestMatchingCommandWithoutLeakingOtherActions() {
    let old = Date(timeIntervalSince1970: 1_700_000_000)
    let new = old.addingTimeInterval(60)
    let state = ReminderCompletionSyncState(taskID: "task-1", audit: [
        audit(id: "other", type: "completeReminder", entityID: "task-2", state: "terminal_failure", at: new),
        audit(id: "older", type: "completeReminder", entityID: "task-1", state: "retryable_failure", at: old),
        audit(id: "latest", type: "completeReminder", entityID: "task-1", state: "pending", at: new),
    ])

    #expect(state.commandID == "latest")
    #expect(state.phase == .pending)
    #expect(state.isAwaitingConfirmation)
    #expect(state.canRetry == false)
}

@Test
func reminderCompletionFailurePreservesHonestRecoveryState() {
    let state = ReminderCompletionSyncState(taskID: "task-1", audit: [
        audit(id: "failed", type: "completeReminder", entityID: "task-1", state: "terminal_failure", attemptCount: 2)
    ])

    #expect(state.phase == .failed)
    #expect(state.canRetry)
    #expect(state.attemptCount == 2)
    #expect(state.userFacingDetail?.contains("local task and history are safe") == true)
}

@Test
func reminderCompletionOnlyClaimsSuccessAfterSourceConfirmation() {
    let pending = ReminderCompletionSyncState(taskID: "task-1", audit: [
        audit(id: "command", type: "completeReminder", entityID: "task-1", state: "executing")
    ])
    let confirmed = ReminderCompletionSyncState(taskID: "task-1", audit: [
        audit(id: "command", type: "completeReminder", entityID: "task-1", state: "succeeded")
    ])

    #expect(pending.phase == .retrying)
    #expect(pending.isAwaitingConfirmation)
    #expect(confirmed.phase == .confirmed)
    #expect(confirmed.isAwaitingConfirmation == false)
}

private func audit(
    id: String,
    type: String,
    entityID: String,
    state: String,
    attemptCount: Int = 0,
    at: Date = Date(timeIntervalSince1970: 1_700_000_000)
) -> ActionAuditEntry {
    ActionAuditEntry(
        id: id,
        actionType: type,
        entityID: entityID,
        state: state,
        attemptCount: attemptCount,
        createdAt: at,
        updatedAt: at,
        canUndo: false
    )
}
