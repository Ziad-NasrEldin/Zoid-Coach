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
            usesCalendarAvailability: true,
            availabilityRevision: revision(commitments: [commitment(id: "meeting")])
        )

        #expect(state.writeState == .reviewing)
        #expect(state.items.map(\.title) == ["Write proposal", "Review budget"])
        #expect(state.plannedMinutes == 90)
        #expect(state.remainingMinutes == 90)
        #expect(state.fixedCommitmentMinutes == 45)
        #expect(state.usesCalendarAvailability)
        #expect(state.preflight(against: revision(commitments: [commitment(id: "meeting")])) == .current)
    }

    @Test("confirm preflight rejects a changed commitment even when occupied minutes stay equal")
    func changedCommitmentRefusesApproval() {
        var state = CalendarPlanApprovalState()
        state.begin(
            entries: [DailyPlanEntry(reminderID: "main", rank: 1, isMainObjective: true, estimateMinutes: 60)],
            titlesByReminderID: ["main": "Write proposal"],
            availableMinutes: 180,
            fixedCommitmentMinutes: 60,
            usesCalendarAvailability: true,
            availabilityRevision: revision(commitments: [commitment(id: "original")])
        )

        #expect(state.preflight(against: revision(commitments: [commitment(id: "replacement")])) == .changed)
        #expect(state.writeState == .reviewing)
        #expect(state.items.map(\.title) == ["Write proposal"])
    }

    @Test("confirm preflight rejects a cancelled reviewed commitment")
    func cancelledCommitmentRefusesApproval() {
        var state = CalendarPlanApprovalState()
        state.begin(
            entries: [DailyPlanEntry(reminderID: "main", rank: 1, isMainObjective: true, estimateMinutes: 60)],
            titlesByReminderID: ["main": "Write proposal"],
            availableMinutes: 180,
            fixedCommitmentMinutes: 60,
            usesCalendarAvailability: true,
            availabilityRevision: revision(commitments: [commitment(id: "cancelled")])
        )

        #expect(state.preflight(against: revision(commitments: [])) == .changed)
        #expect(state.items.map(\.id) == ["main"])
    }

    @Test("confirm preflight rejects unavailable Calendar without changing the reviewed plan")
    func unavailableCalendarRefusesApproval() {
        var state = CalendarPlanApprovalState()
        state.begin(
            entries: [DailyPlanEntry(reminderID: "main", rank: 1, isMainObjective: true, estimateMinutes: 60)],
            titlesByReminderID: ["main": "Write proposal"],
            availableMinutes: 180,
            fixedCommitmentMinutes: 60,
            usesCalendarAvailability: true,
            availabilityRevision: revision(commitments: [commitment(id: "meeting")])
        )

        #expect(state.preflight(against: nil) == .unavailable)
        #expect(state.writeState == .reviewing)
        #expect(state.plannedMinutes == 60)
    }

    @Test("a review created while Calendar is unavailable cannot be confirmed")
    func unavailableReviewRefusesApproval() {
        var state = CalendarPlanApprovalState()
        state.begin(
            entries: [DailyPlanEntry(reminderID: "main", rank: 1, isMainObjective: true, estimateMinutes: 60)],
            titlesByReminderID: ["main": "Write proposal"],
            availableMinutes: 240,
            fixedCommitmentMinutes: 0,
            usesCalendarAvailability: false
        )

        #expect(state.preflight(against: revision(commitments: [])) == .unavailable)
        #expect(state.items.map(\.title) == ["Write proposal"])
    }

    @Test("Calendar-unavailable review can be approved locally without write identities")
    func unavailableReviewAcceptsLocalPlan() throws {
        let approvedAt = Date(timeIntervalSince1970: 1_800_000_000)
        var state = CalendarPlanApprovalState()
        state.begin(
            entries: [DailyPlanEntry(reminderID: "main", rank: 1, isMainObjective: true, estimateMinutes: 60)],
            titlesByReminderID: ["main": "Write proposal"],
            availableMinutes: 240,
            fixedCommitmentMinutes: 0,
            usesCalendarAvailability: false
        )

        let accepted = state.acceptLocally(approvedAt: approvedAt)
        #expect(accepted)
        #expect(state.writeState == .applied(commandCount: 0))
        let receipt = try #require(state.receipt)
        #expect(receipt.items.map(\.title) == ["Write proposal"])
        #expect(receipt.commandIDs.isEmpty)
        #expect(receipt.commandCount == 0)
        #expect(!receipt.usesCalendarAvailability)
        #expect(receipt.approvedAt == approvedAt)
        #expect(receipt.summary == "Plan approved locally. No Calendar or Reminder changes were requested.")

        var restored = CalendarPlanApprovalState()
        restored.restore(receipt)
        #expect(restored.writeState == .applied(commandCount: 0))
        #expect(restored.items.map(\.title) == ["Write proposal"])
        #expect(!restored.isPresented)
    }

    @Test("local approval is refused when Calendar-backed write review is available")
    func availableReviewCannotMasqueradeAsLocalOnly() {
        var state = CalendarPlanApprovalState()
        state.begin(
            entries: [DailyPlanEntry(reminderID: "main", rank: 1, isMainObjective: true, estimateMinutes: 60)],
            titlesByReminderID: ["main": "Write proposal"],
            availableMinutes: 180,
            fixedCommitmentMinutes: 30,
            usesCalendarAvailability: true,
            availabilityRevision: revision(commitments: [commitment(id: "meeting")])
        )

        let accepted = state.acceptLocally()
        #expect(!accepted)
        #expect(state.writeState == .reviewing)
        #expect(state.receipt == nil)
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

    @Test("authoritative zero-write refusal clears a pre-send reconciling receipt")
    func authoritativeRefusalClearsReconcilingReceipt() throws {
        let suite = "calendar-plan-refusal-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = CalendarPlanApprovalReceiptStore(defaults: defaults)
        var state = CalendarPlanApprovalState()
        state.begin(
            entries: [DailyPlanEntry(reminderID: "main", rank: 1, isMainObjective: true, estimateMinutes: 45)],
            titlesByReminderID: ["main": "Write proposal"],
            availableMinutes: 120,
            fixedCommitmentMinutes: 30,
            usesCalendarAvailability: true
        )
        state.markReconciling()
        try store.save(try #require(state.receipt))

        let accepted = CalendarPlanReceiptReconciler.apply(
            AgentMutationReceipt(
                accepted: false,
                message: "Calendar availability changed. Nothing was written."
            ),
            to: &state,
            store: store
        )

        #expect(!accepted)
        #expect(state.writeState == .reviewing)
        #expect(state.receipt == nil)
        #expect(store.load() == nil)
    }

    @Test("partial command progress remains pending across receipt restore")
    func partialProgressRestoresPending() throws {
        var state = CalendarPlanApprovalState()
        state.queued(commandIDs: ["calendar", "reminder"])
        state.reconcile(with: [
            audit("calendar", .succeeded),
            audit("reminder", .retryableFailure)
        ])

        #expect(state.writeState == .pending(commandIDs: ["calendar", "reminder"]))
        #expect(state.receipt?.outcome == .pending)
        #expect(state.receipt?.commandCount == 2)

        var restored = CalendarPlanApprovalState()
        restored.restore(try #require(state.receipt))
        #expect(restored.writeState == .pending(commandIDs: ["calendar", "reminder"]))

        restored.reconcile(with: [
            audit("calendar", .succeeded),
            audit("reminder", .succeeded)
        ])
        #expect(restored.writeState == .applied(commandCount: 2))
        #expect(restored.receipt?.summary == "Approved plan confirmed. 2 Calendar changes applied.")
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

    @Test("partial failure retry is issued once and preserves the original total")
    func partialFailureRetryPreservesTotal() throws {
        var state = CalendarPlanApprovalState()
        state.queued(commandIDs: ["calendar", "reminder"])
        state.reconcile(with: [
            audit("calendar", .terminalFailure),
            audit("reminder", .succeeded)
        ])

        #expect(state.writeState == .failed(commandIDs: ["calendar"]))
        #expect(state.receipt?.commandIDs == ["calendar"])
        #expect(state.receipt?.commandCount == 2)

        var restored = CalendarPlanApprovalState()
        restored.restore(try #require(state.receipt))
        #expect(restored.retryFailedCommands() == ["calendar"])
        #expect(restored.retryFailedCommands().isEmpty)
        #expect(restored.receipt?.outcome == .pending)
        #expect(restored.receipt?.commandCount == 2)

        restored.reconcile(with: [audit("calendar", .succeeded)])
        #expect(restored.writeState == .applied(commandCount: 2))
        #expect(restored.receipt?.commandCount == 2)
        #expect(restored.receipt?.summary == "Approved plan confirmed. 2 Calendar changes applied.")
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

    private func revision(commitments: [ZoidCoachApp.CalendarCommitment]) -> CalendarPlanAvailabilityRevision {
        CalendarPlanAvailabilityRevision(
            workIntervals: [
                CalendarInterval(
                    start: Date(timeIntervalSince1970: 1_800_000_000),
                    end: Date(timeIntervalSince1970: 1_800_028_800)
                )
            ],
            visibleCalendarIdentifiers: ["work"],
            commitments: commitments
        )
    }

    private func commitment(id: String) -> ZoidCoachApp.CalendarCommitment {
        ZoidCoachApp.CalendarCommitment(
            id: id,
            title: "Meeting",
            start: Date(timeIntervalSince1970: 1_800_003_600),
            end: Date(timeIntervalSince1970: 1_800_007_200),
            calendarIdentifier: "work",
            isZoidOwned: false
        )
    }
}
