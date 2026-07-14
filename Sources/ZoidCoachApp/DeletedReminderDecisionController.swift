import Foundation
import ZoidCoachCore
import ZoidCoachInfrastructure

protocol DeletedReminderDecisionServicing: AnyObject {
    func deletedReminderDecisions() throws -> [DeletedReminderDecision]
    func keepDeletedReminderInLocalHistory(sourceID: String, decidedAt: Date) throws -> Bool
    func removeDeletedReminderLocalCopy(sourceID: String) throws -> Bool
}

extension ReminderSnapshotStore: DeletedReminderDecisionServicing {}

struct DeletedReminderDecisionPresentation: Equatable, Sendable {
    let title: String
    let detail: String
    let status: String
    let rowAccessibilityID: String
    let keepAccessibilityID: String
    let removeAccessibilityID: String

    init(decision: DeletedReminderDecision) {
        title = decision.title
        let list = decision.listName.map { "List: \($0)." } ?? "No list name was stored."
        let due = decision.dueDate.map { "Due \($0.formatted(date: .abbreviated, time: .omitted))." }
            ?? "No due date was stored."
        detail = "Apple Reminders no longer contains this task. \(list) \(due) Notes and Reminder content are not copied here."
        status = decision.state == .kept ? "KEPT IN LOCAL HISTORY" : "CHOOSE WHAT TO KEEP"
        let stableID = String(decision.sourceID.map { character in
            character.isLetter || character.isNumber ? character : "-"
        })
        rowAccessibilityID = "settings.reminders.deleted.\(stableID)"
        keepAccessibilityID = "\(rowAccessibilityID).keep"
        removeAccessibilityID = "\(rowAccessibilityID).remove"
    }
}

struct DeletedReminderRemovalConfirmation: Equatable, Sendable {
    let title: String
    let message: String

    init(decision: DeletedReminderDecision) {
        title = "Remove local copy of \(decision.title)?"
        message = "This removes only Zoid 666's saved copy of \(decision.title). It does not change Apple Reminders or any other task history. This cannot be undone."
    }
}

@MainActor
final class DeletedReminderDecisionController: ObservableObject {
    @Published private(set) var decisions: [DeletedReminderDecision] = []
    @Published private(set) var feedback: String?
    @Published private(set) var errorMessage: String?
    @Published private(set) var isWorking = false

    private let service: DeletedReminderDecisionServicing
    private let now: () -> Date

    init(service: DeletedReminderDecisionServicing, now: @escaping () -> Date = Date.init) {
        self.service = service
        self.now = now
    }

    convenience init(runtimeEnvironment: RuntimeEnvironment = .current()) {
        do {
            let service = try ReminderSnapshotStore(databaseURL: runtimeEnvironment.databaseURL)
            self.init(service: service)
        } catch {
            self.init(service: UnavailableDeletedReminderDecisionService(error: error))
        }
    }

    func refresh() {
        do {
            decisions = try service.deletedReminderDecisions()
            errorMessage = nil
        } catch {
            errorMessage = "Deleted Reminder choices could not be loaded. No local history was changed."
        }
    }

    func keep(_ decision: DeletedReminderDecision) {
        perform(success: "Kept \(decision.title) in local history.") {
            try service.keepDeletedReminderInLocalHistory(sourceID: decision.sourceID, decidedAt: now())
        }
    }

    func removeConfirmed(_ decision: DeletedReminderDecision) {
        perform(success: "Removed the local copy of \(decision.title).") {
            try service.removeDeletedReminderLocalCopy(sourceID: decision.sourceID)
        }
    }

    private func perform(success: String, operation: () throws -> Bool) {
        isWorking = true
        feedback = nil
        defer { isWorking = false }
        do {
            guard try operation() else {
                errorMessage = "This deleted Reminder changed before the choice was saved. Refresh and try again."
                return
            }
            feedback = success
            errorMessage = nil
            decisions = try service.deletedReminderDecisions()
        } catch {
            errorMessage = "The choice could not be saved. No other task or history was changed."
        }
    }
}

private final class UnavailableDeletedReminderDecisionService: DeletedReminderDecisionServicing {
    private let error: Error

    init(error: Error) { self.error = error }

    func deletedReminderDecisions() throws -> [DeletedReminderDecision] { throw error }
    func keepDeletedReminderInLocalHistory(sourceID: String, decidedAt: Date) throws -> Bool { throw error }
    func removeDeletedReminderLocalCopy(sourceID: String) throws -> Bool { throw error }
}
