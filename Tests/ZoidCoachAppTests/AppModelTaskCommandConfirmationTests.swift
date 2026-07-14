import Testing
@testable import ZoidCoachApp
@testable import ZoidCoachCore

@MainActor
@Test
func localTaskCompletionConfirmationNeverClaimsRemindersSync() {
    let message = AppModel.taskCommandConfirmation(
        .complete,
        taskID: "local:user:completion-copy"
    )

    #expect(message == "Local task completed on this Mac.")
    #expect(!message.localizedCaseInsensitiveContains("Reminders"))
    #expect(!message.localizedCaseInsensitiveContains("queued"))
    #expect(!message.localizedCaseInsensitiveContains("sync"))
}

@MainActor
@Test
func externalReminderCompletionConfirmationNamesPendingSync() {
    let message = AppModel.taskCommandConfirmation(
        .complete,
        taskID: "apple-reminder-1"
    )

    #expect(message == "Task completion is pending Reminders sync.")
}
