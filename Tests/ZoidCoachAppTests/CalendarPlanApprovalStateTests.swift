import Foundation
import Testing
@testable import ZoidCoachApp
import ZoidCoachCore

@Suite("Calendar plan approval")
struct CalendarPlanApprovalStateTests {
    @Test("preview shows exact reviewed tasks and conflict-aware capacity")
    func preview() {
        var state = CalendarPlanApprovalState()
        state.begin(
            entries: [
                DailyPlanEntry(reminderID: "b", rank: 2, isMainObjective: false, estimateMinutes: 30),
                DailyPlanEntry(reminderID: "a", rank: 1, isMainObjective: true, estimateMinutes: 60)
            ],
            titlesByReminderID: ["a": "Write proposal", "b": "Review budget"],
            availableMinutes: 180,
            fixedCommitmentMinutes: 45,
            usesCalendarAvailability: true
        )

        #expect(state.writeState == .reviewing)
        #expect(state.items.map(\.title) == ["Write proposal", "Review budget"])
        #expect(state.plannedMinutes == 90)
        #expect(state.remainingMinutes == 90)
        #expect(state.fixedCommitmentMinutes == 45)
        #expect(state.usesCalendarAvailability)
    }

    @Test("write receipt stays pending until every exact command succeeds")
    func pendingThenApplied() {
        var state = CalendarPlanApprovalState()
        state.queued(commandIDs: ["calendar", "reminder"])

        state.reconcile(with: [audit("calendar", .succeeded)])
        #expect(state.writeState == .pending(commandIDs: ["calendar", "reminder"]))

        state.reconcile(with: [
            audit("calendar", .succeeded),
            audit("reminder", .succeeded)
        ])
        #expect(state.writeState == .applied(commandCount: 2))
        #expect(state.receipt?.outcome == .applied)
        #expect(state.receipt?.commandCount == 2)
    }

    @Test("terminal failure is never presented as a Calendar confirmation")
    func terminalFailure() {
        var state = CalendarPlanApprovalState()
        state.queued(commandIDs: ["calendar", "reminder"])
        state.reconcile(with: [
            audit("calendar", .terminalFailure),
            audit("reminder", .succeeded)
        ])

        #expect(state.writeState == .failed(commandIDs: ["calendar"]))
    }

    @Test("cancelled writes are never presented as Calendar confirmation")
    func cancelledWrite() {
        var state = CalendarPlanApprovalState()
        state.queued(commandIDs: ["calendar", "reminder"])
        state.reconcile(with: [
            audit("calendar", .cancelled),
            audit("reminder", .succeeded)
        ])

        #expect(state.writeState == .failed(commandIDs: ["calendar"]))
    }

    @Test("duplicate command identifiers remain one tracked write")
    func duplicateReceipt() {
        var state = CalendarPlanApprovalState()
        state.queued(commandIDs: ["calendar", "calendar"])
        #expect(state.writeState == .pending(commandIDs: ["calendar"]))
    }

    @Test("durable receipt restores without reopening the approval modal")
    func durableReceiptRestoresWithoutRepeatingApproval() throws {
        let suite = "calendar-plan-receipt-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = CalendarPlanApprovalReceiptStore(defaults: defaults)
        let approvedAt = Date(timeIntervalSince1970: 1_800_000_000)
        var original = CalendarPlanApprovalState()
        original.begin(
            entries: [DailyPlanEntry(reminderID: "main", rank: 1, isMainObjective: true, estimateMinutes: 45)],
            titlesByReminderID: ["main": "Write proposal"],
            availableMinutes: 120,
            fixedCommitmentMinutes: 30,
            usesCalendarAvailability: true
        )
        original.queued(commandIDs: ["calendar", "reminder"], approvedAt: approvedAt)
        let receipt = try #require(original.receipt)
        try store.save(receipt)

        var restored = CalendarPlanApprovalState()
        restored.restore(try #require(store.load()))

        #expect(!restored.isPresented)
        #expect(restored.items.map(\.title) == ["Write proposal"])
        #expect(restored.writeState == .pending(commandIDs: ["calendar", "reminder"]))
        #expect(restored.receipt?.approvedAt == approvedAt)
        #expect(restored.receipt?.summary.contains("2 Calendar changes are still pending") == true)

        restored.presentReceipt()
        #expect(restored.isPresented)
        restored.dismiss()
        #expect(!restored.isPresented)
        #expect(restored.receipt != nil)
    }

    @Test("terminal failure retries the exact receipt command identity")
    func terminalFailureRetriesExactReceiptCommands() {
        var state = CalendarPlanApprovalState()
        state.begin(
            entries: [DailyPlanEntry(reminderID: "main", rank: 1, isMainObjective: true, estimateMinutes: 45)],
            titlesByReminderID: ["main": "Write proposal"],
            availableMinutes: 120,
            fixedCommitmentMinutes: 30,
            usesCalendarAvailability: true
        )
        state.queued(commandIDs: ["calendar", "reminder"])
        state.reconcile(with: [
            audit("calendar", .terminalFailure),
            audit("reminder", .succeeded)
        ])

        #expect(state.writeState == .failed(commandIDs: ["calendar"]))
        #expect(state.retryFailedCommands() == ["calendar"])
        #expect(state.writeState == .pending(commandIDs: ["calendar"]))
        #expect(state.receipt?.commandIDs == ["calendar"])
        #expect(state.receipt?.outcome == .pending)

        state.retryRequestFailed(commandIDs: ["calendar"])
        #expect(state.writeState == .failed(commandIDs: ["calendar"]))
        #expect(state.receipt?.outcome == .failed)
    }

    private func audit(_ id: String, _ state: ActionCommandState) -> ActionAuditEntry {
        ActionAuditEntry(
            id: id,
            actionType: ActionCommandType.reconcileCalendarBlock.rawValue,
            entityID: id,
            state: state.rawValue,
            attemptCount: state == .succeeded ? 1 : 3,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_700_000_001),
            canUndo: state == .succeeded
        )
    }
}
