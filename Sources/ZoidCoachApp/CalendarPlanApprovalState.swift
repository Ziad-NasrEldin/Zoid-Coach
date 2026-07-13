import Foundation
import ZoidCoachCore

struct CalendarPlanApprovalItem: Codable, Equatable, Identifiable, Sendable {
    let reminderID: String
    let title: String
    let rank: Int
    let estimateMinutes: Int
    let estimateIsUncertain: Bool?
    let isMainObjective: Bool

    init(
        reminderID: String,
        title: String,
        rank: Int,
        estimateMinutes: Int,
        estimateIsUncertain: Bool = false,
        isMainObjective: Bool
    ) {
        self.reminderID = reminderID
        self.title = title
        self.rank = rank
        self.estimateMinutes = estimateMinutes
        self.estimateIsUncertain = estimateIsUncertain
        self.isMainObjective = isMainObjective
    }

    var id: String { reminderID }
}

struct CalendarPlanAvailabilityRevision: Equatable, Sendable {
    struct Commitment: Equatable, Sendable {
        let id: String
        let start: Date
        let end: Date
        let calendarIdentifier: String
    }

    let workIntervals: [CalendarInterval]
    let visibleCalendarIdentifiers: [String]
    let commitments: [Commitment]

    init(
        workIntervals: [CalendarInterval],
        visibleCalendarIdentifiers: Set<String>,
        commitments: [CalendarCommitment]
    ) {
        self.workIntervals = workIntervals.sorted {
            if $0.start != $1.start { return $0.start < $1.start }
            return $0.end < $1.end
        }
        self.visibleCalendarIdentifiers = visibleCalendarIdentifiers.sorted()
        self.commitments = commitments
            .filter { commitment in
                !commitment.isZoidOwned
                    && workIntervals.contains {
                        commitment.end > $0.start && commitment.start < $0.end
                    }
            }
            .map {
                Commitment(
                    id: $0.id,
                    start: $0.start,
                    end: $0.end,
                    calendarIdentifier: $0.calendarIdentifier
                )
            }
            .sorted {
                if $0.start != $1.start { return $0.start < $1.start }
                if $0.end != $1.end { return $0.end < $1.end }
                if $0.calendarIdentifier != $1.calendarIdentifier {
                    return $0.calendarIdentifier < $1.calendarIdentifier
                }
                return $0.id < $1.id
            }
    }
}

enum CalendarPlanAvailabilityPreflight: Equatable, Sendable {
    case current
    case changed
    case unavailable
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
    private var reviewedAvailabilityRevision: CalendarPlanAvailabilityRevision?

    var isPresented: Bool { presentationIsOpen }
    var plannedMinutes: Int { items.reduce(0) { $0 + $1.estimateMinutes } }
    var remainingMinutes: Int { max(0, availableMinutes - plannedMinutes) }

    mutating func begin(
        entries: [DailyPlanEntry],
        titlesByReminderID: [String: String],
        availableMinutes: Int,
        fixedCommitmentMinutes: Int,
        usesCalendarAvailability: Bool,
        availabilityRevision: CalendarPlanAvailabilityRevision? = nil
    ) {
        items = entries.compactMap { entry in
            let estimate = entry.estimateMinutes
                ?? (entry.estimateIsUncertain ? PlanningCapacityState.unknownEstimatePlaceholderMinutes : nil)
            guard let estimate else { return nil }
            return CalendarPlanApprovalItem(
                reminderID: entry.reminderID,
                title: titlesByReminderID[entry.reminderID] ?? "Unavailable reminder",
                rank: entry.rank,
                estimateMinutes: estimate,
                estimateIsUncertain: entry.estimateIsUncertain,
                isMainObjective: entry.isMainObjective
            )
        }.sorted { $0.rank < $1.rank }
        self.availableMinutes = availableMinutes
        self.fixedCommitmentMinutes = fixedCommitmentMinutes
        self.usesCalendarAvailability = usesCalendarAvailability
        reviewedAvailabilityRevision = availabilityRevision
        writeState = .reviewing
        presentationIsOpen = true
    }

    func preflight(
        against currentRevision: CalendarPlanAvailabilityRevision?
    ) -> CalendarPlanAvailabilityPreflight {
        guard let currentRevision else { return .unavailable }
        guard let reviewedAvailabilityRevision else { return .unavailable }
        return reviewedAvailabilityRevision == currentRevision ? .current : .changed
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

    mutating func retryFailedCommands() -> [String] {
        guard case let .failed(commandIDs) = writeState else { return [] }
        writeState = .pending(commandIDs: commandIDs)
        updateReceipt(outcome: .pending, commandIDs: commandIDs, commandCount: commandIDs.count)
        return commandIDs.sorted()
    }

    mutating func retryRequestFailed(commandIDs: [String]) {
        let identifiers = Set(commandIDs)
        writeState = .failed(commandIDs: identifiers)
        updateReceipt(outcome: .failed, commandIDs: identifiers, commandCount: identifiers.count)
    }

    mutating func restore(_ receipt: CalendarPlanApprovalReceipt) {
        self.receipt = receipt
        items = receipt.items
        availableMinutes = receipt.availableMinutes
        fixedCommitmentMinutes = receipt.fixedCommitmentMinutes
        usesCalendarAvailability = receipt.usesCalendarAvailability
        reviewedAvailabilityRevision = nil
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
