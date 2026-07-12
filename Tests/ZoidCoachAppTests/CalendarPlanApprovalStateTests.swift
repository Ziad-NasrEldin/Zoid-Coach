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

    @Test("duplicate command identifiers remain one tracked write")
    func duplicateReceipt() {
        var state = CalendarPlanApprovalState()
        state.queued(commandIDs: ["calendar", "calendar"])
        #expect(state.writeState == .pending(commandIDs: ["calendar"]))
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
