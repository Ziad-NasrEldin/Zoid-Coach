import Foundation
import ZoidCoachCore

struct CalendarPlanApprovalItem: Codable, Equatable, Identifiable, Sendable {
    let reminderID: String
    let title: String
    let rank: Int
    let estimateMinutes: Int
    let isMainObjective: Bool

    var id: String { reminderID }
}

enum CalendarPlanWriteState: Equatable, Sendable {
    case idle
    case reviewing
    case queueing
    case pending(commandIDs: Set<String>)
    case applied(commandCount: Int)
    case failed(commandIDs: Set<String>)
}

enum CalendarPlanReceiptOutcome: String, Codable, Equatable, Sendable {
    case pending
    case applied
    case failed
}

struct CalendarPlanApprovalReceipt: Codable, Equatable, Sendable {
    let items: [CalendarPlanApprovalItem]
    let availableMinutes: Int
    let fixedCommitmentMinutes: Int
    let usesCalendarAvailability: Bool
    let commandIDs: Set<String>
    let outcome: CalendarPlanReceiptOutcome
    let commandCount: Int
    let approvedAt: Date

    var summary: String {
        let taskCount = items.count
        switch outcome {
        case .pending:
            return "Approved \(taskCount) task\(taskCount == 1 ? "" : "s"). \(commandIDs.count) Calendar change\(commandIDs.count == 1 ? " is" : "s are") still pending."
        case .applied:
            return "Approved plan confirmed. \(commandCount) Calendar change\(commandCount == 1 ? "" : "s") applied."
        case .failed:
            return "Approved plan kept locally. \(commandIDs.count) Calendar change\(commandIDs.count == 1 ? " needs" : "s need") repair."
        }
    }
}

struct CalendarPlanApprovalState: Equatable, Sendable {
    var items: [CalendarPlanApprovalItem] = []
    var availableMinutes = 0
    var fixedCommitmentMinutes = 0
    var usesCalendarAvailability = false
    var writeState: CalendarPlanWriteState = .idle
    private(set) var receipt: CalendarPlanApprovalReceipt?
    private var presentationIsOpen = false

    var isPresented: Bool { presentationIsOpen }
    var plannedMinutes: Int { items.reduce(0) { $0 + $1.estimateMinutes } }
    var remainingMinutes: Int { max(0, availableMinutes - plannedMinutes) }

    mutating func begin(
        entries: [DailyPlanEntry],
        titlesByReminderID: [String: String],
        availableMinutes: Int,
        fixedCommitmentMinutes: Int,
        usesCalendarAvailability: Bool
    ) {
        items = entries.compactMap { entry in
            guard let estimate = entry.estimateMinutes else { return nil }
            return CalendarPlanApprovalItem(
                reminderID: entry.reminderID,
                title: titlesByReminderID[entry.reminderID] ?? "Unavailable reminder",
                rank: entry.rank,
                estimateMinutes: estimate,
                isMainObjective: entry.isMainObjective
            )
        }.sorted { $0.rank < $1.rank }
        self.availableMinutes = availableMinutes
        self.fixedCommitmentMinutes = fixedCommitmentMinutes
        self.usesCalendarAvailability = usesCalendarAvailability
        writeState = .reviewing
        presentationIsOpen = true
    }

    mutating func queued(commandIDs: [String], approvedAt: Date = Date()) {
        let identifiers = Set(commandIDs)
        writeState = identifiers.isEmpty ? .applied(commandCount: 0) : .pending(commandIDs: identifiers)
        receipt = CalendarPlanApprovalReceipt(
            items: items,
            availableMinutes: availableMinutes,
            fixedCommitmentMinutes: fixedCommitmentMinutes,
            usesCalendarAvailability: usesCalendarAvailability,
            commandIDs: identifiers,
            outcome: identifiers.isEmpty ? .applied : .pending,
            commandCount: identifiers.isEmpty ? 0 : identifiers.count,
            approvedAt: approvedAt
        )
    }

    mutating func reconcile(with audit: [ActionAuditEntry]) {
        guard case let .pending(commandIDs) = writeState else { return }
        let relevant = audit.filter { commandIDs.contains($0.id) }
        guard relevant.count == commandIDs.count else { return }
        let failed = relevant.filter {
            $0.state == ActionCommandState.terminalFailure.rawValue
                || $0.state == ActionCommandState.cancelled.rawValue
        }
        if !failed.isEmpty {
            writeState = .failed(commandIDs: Set(failed.map(\.id)))
            updateReceipt(outcome: .failed, commandIDs: Set(failed.map(\.id)), commandCount: failed.count)
        } else if relevant.allSatisfy({ $0.state == ActionCommandState.succeeded.rawValue }) {
            writeState = .applied(commandCount: relevant.count)
            updateReceipt(outcome: .applied, commandIDs: commandIDs, commandCount: relevant.count)
        }
    }

    mutating func dismiss() {
        presentationIsOpen = false
    }

    mutating func presentReceipt() {
        guard receipt != nil else { return }
        presentationIsOpen = true
    }

    mutating func restore(_ receipt: CalendarPlanApprovalReceipt) {
        self.receipt = receipt
        items = receipt.items
        availableMinutes = receipt.availableMinutes
        fixedCommitmentMinutes = receipt.fixedCommitmentMinutes
        usesCalendarAvailability = receipt.usesCalendarAvailability
        presentationIsOpen = false
        switch receipt.outcome {
        case .pending:
            writeState = .pending(commandIDs: receipt.commandIDs)
        case .applied:
            writeState = .applied(commandCount: receipt.commandCount)
        case .failed:
            writeState = .failed(commandIDs: receipt.commandIDs)
        }
    }

    private mutating func updateReceipt(
        outcome: CalendarPlanReceiptOutcome,
        commandIDs: Set<String>,
        commandCount: Int
    ) {
        guard let receipt else { return }
        self.receipt = CalendarPlanApprovalReceipt(
            items: receipt.items,
            availableMinutes: receipt.availableMinutes,
            fixedCommitmentMinutes: receipt.fixedCommitmentMinutes,
            usesCalendarAvailability: receipt.usesCalendarAvailability,
            commandIDs: commandIDs,
            outcome: outcome,
            commandCount: commandCount,
            approvedAt: receipt.approvedAt
        )
    }
}
