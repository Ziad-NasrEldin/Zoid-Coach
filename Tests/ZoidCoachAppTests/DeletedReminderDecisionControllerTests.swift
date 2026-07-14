import Foundation
import Testing
@testable import ZoidCoachApp
import ZoidCoachInfrastructure

@Test @MainActor
func deletedReminderControllerKeepsAndReloadsVisibleHistory() {
    let decision = deletedDecision()
    let service = DeletedReminderDecisionServiceStub(decisions: [decision])
    let controller = DeletedReminderDecisionController(
        service: service,
        now: { Date(timeIntervalSince1970: 1_750_000_100) }
    )
    controller.refresh()

    controller.keep(decision)

    #expect(service.keptIDs == [decision.sourceID])
    #expect(controller.decisions.first?.state == .kept)
    #expect(controller.feedback == "Kept Deleted task in local history.")
    #expect(controller.errorMessage == nil)
}

@Test @MainActor
func deletedReminderControllerRemovesOnlyAfterConfirmedMethod() {
    let decision = deletedDecision()
    let service = DeletedReminderDecisionServiceStub(decisions: [decision])
    let controller = DeletedReminderDecisionController(service: service)
    controller.refresh()
    #expect(service.removedIDs.isEmpty)

    controller.removeConfirmed(decision)

    #expect(service.removedIDs == [decision.sourceID])
    #expect(controller.decisions.isEmpty)
}

@Test @MainActor
func deletedReminderSaveErrorStaysVisibleAndCanBeRetried() {
    let decision = deletedDecision()
    let service = DeletedReminderDecisionServiceStub(decisions: [decision])
    service.shouldFail = true
    let controller = DeletedReminderDecisionController(service: service)
    controller.refresh()

    controller.keep(decision)

    #expect(controller.errorMessage == "The choice could not be saved. No other task or history was changed.")
    #expect(controller.decisions == [decision])

    service.shouldFail = false
    controller.keep(decision)

    #expect(controller.errorMessage == nil)
    #expect(controller.decisions.first?.state == .kept)
}

@Test @MainActor
func successfulDeletedReminderChoiceReportsReloadFailureTruthfullyAndCanReload() {
    let decision = deletedDecision()
    let service = DeletedReminderDecisionServiceStub(decisions: [decision])
    let controller = DeletedReminderDecisionController(service: service)
    controller.refresh()
    service.shouldFailRefresh = true

    controller.keep(decision)

    #expect(service.keptIDs == [decision.sourceID])
    #expect(controller.feedback == "Kept Deleted task in local history.")
    #expect(controller.errorMessage == "The choice was saved, but deleted Reminder choices could not be reloaded. Reload to see the saved state.")
    #expect(controller.decisions.isEmpty)

    service.shouldFailRefresh = false
    controller.refresh()

    #expect(controller.errorMessage == nil)
    #expect(controller.decisions.first?.state == .kept)
}

@Test
func deletedReminderPresentationUsesPrivacySafeCopyAndStableAccessibilityIDs() {
    let presentation = DeletedReminderDecisionPresentation(decision: deletedDecision())

    #expect(presentation.detail.contains("Apple Reminders no longer contains this task"))
    #expect(presentation.detail.contains("The title shown here was retained"))
    #expect(presentation.detail.contains("Notes, links, and other Reminder content were not copied"))
    #expect(!presentation.detail.contains("Private client details"))
    #expect(presentation.status == "CHOOSE WHAT TO KEEP")
    #expect(presentation.rowAccessibilityID == "settings.reminders.deleted.72656d696e6465722d31")
    #expect(presentation.keepAccessibilityID.hasSuffix(".keep"))
    #expect(presentation.removeAccessibilityID.hasSuffix(".remove"))

    let slash = DeletedReminderDecisionPresentation(decision: deletedDecision(sourceID: "a/b"))
    let dash = DeletedReminderDecisionPresentation(decision: deletedDecision(sourceID: "a-b"))
    #expect(slash.rowAccessibilityID != dash.rowAccessibilityID)
}

@Test
func deletedReminderRemovalConfirmationNamesOnlyTheChosenTask() {
    let confirmation = DeletedReminderRemovalConfirmation(decision: deletedDecision())

    #expect(confirmation.title == "Remove local copy of Deleted task?")
    #expect(confirmation.message.contains("saved copy of Deleted task"))
    #expect(confirmation.message.contains("does not change Apple Reminders or any other task history"))
}

private func deletedDecision(
    sourceID: String = "reminder-1",
    state: DeletedReminderDecisionState = .pending
) -> DeletedReminderDecision {
    DeletedReminderDecision(
        sourceID: sourceID,
        title: "Deleted task",
        dueDate: nil,
        listName: "Work",
        deletedAt: Date(timeIntervalSince1970: 1_750_000_000),
        state: state,
        decidedAt: nil
    )
}

private final class DeletedReminderDecisionServiceStub: DeletedReminderDecisionServicing {
    var decisions: [DeletedReminderDecision]
    var keptIDs: [String] = []
    var removedIDs: [String] = []
    var shouldFail = false
    var shouldFailRefresh = false

    init(decisions: [DeletedReminderDecision]) { self.decisions = decisions }

    func deletedReminderDecisions() throws -> [DeletedReminderDecision] {
        if shouldFailRefresh { throw DeletedReminderDecisionStubError.read }
        return decisions
    }

    func keepDeletedReminderInLocalHistory(sourceID: String, decidedAt: Date) throws -> Bool {
        if shouldFail { throw DeletedReminderDecisionStubError.write }
        keptIDs.append(sourceID)
        decisions = decisions.map {
            guard $0.sourceID == sourceID else { return $0 }
            return DeletedReminderDecision(
                sourceID: $0.sourceID,
                title: $0.title,
                dueDate: $0.dueDate,
                listName: $0.listName,
                deletedAt: $0.deletedAt,
                state: .kept,
                decidedAt: decidedAt
            )
        }
        return true
    }

    func removeDeletedReminderLocalCopy(sourceID: String) throws -> Bool {
        if shouldFail { throw DeletedReminderDecisionStubError.write }
        removedIDs.append(sourceID)
        decisions.removeAll { $0.sourceID == sourceID }
        return true
    }
}

private enum DeletedReminderDecisionStubError: Error {
    case read
    case write
}
