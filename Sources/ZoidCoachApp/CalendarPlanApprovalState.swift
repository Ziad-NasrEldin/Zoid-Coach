import Foundation
import ZoidCoachCore

struct CalendarPlanApprovalItem: Codable, Equatable, Identifiable, Sendable {
    let reminderID: String
    let title: String
    let rank: Int
    let estimateMinutes: Int
    let estimateIsUncertain: Bool?
    let isMainObjective: Bool
    let executionState: TaskExecutionState?

    init(
        reminderID: String,
        title: String,
        rank: Int,
        estimateMinutes: Int,
        estimateIsUncertain: Bool = false,
        isMainObjective: Bool,
        executionState: TaskExecutionState? = nil
    ) {
        self.reminderID = reminderID
        self.title = title
        self.rank = rank
        self.estimateMinutes = estimateMinutes
        self.estimateIsUncertain = estimateIsUncertain
        self.isMainObjective = isMainObjective
        self.executionState = executionState
    }

    var id: String { reminderID }

    var isIncompletePriorityTask: Bool {
        isMainObjective && executionState.map { $0 != .completed } == true
    }

    var priorityStateLabel: String? {
        guard isMainObjective else { return nil }
        return switch executionState {
        case .completed: "PRIORITY · COMPLETE"
        case .some: "PRIORITY · INCOMPLETE"
        case nil: "PRIORITY · STATUS UNKNOWN"
        }
    }

    var priorityStateAccessibilityValue: String? {
        guard isMainObjective else { return nil }
        return switch executionState {
        case .completed: "Complete"
        case .some: "Incomplete"
        case nil: "Status unknown"
        }
    }
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
    case reconciling
    case pending(commandIDs: Set<String>)
    case applied(commandCount: Int)
    case failed(commandIDs: Set<String>)
}

enum CalendarPlanReceiptOutcome: String, Codable, Equatable, Sendable {
    case reconciling
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
        case .reconciling:
            return "The approved plan may already be queued. Zoid 666 is reconciling its exact Calendar and Reminder receipt."
        case .pending:
            return "Approved \(taskCount) task\(taskCount == 1 ? "" : "s"). \(commandIDs.count) Calendar change\(commandIDs.count == 1 ? " is" : "s are") still pending."
        case .applied:
            if !usesCalendarAvailability, commandCount == 0 {
                return "Plan approved locally. No Calendar or Reminder changes were requested."
            }
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
    private(set) var queueRequestedAt: Date?
    private var reviewedAvailabilityRevision: CalendarPlanAvailabilityRevision?

    var isPresented: Bool { presentationIsOpen }
    var plannedMinutes: Int { items.reduce(0) { $0 + $1.estimateMinutes } }
    var remainingMinutes: Int { max(0, availableMinutes - plannedMinutes) }

    mutating func begin(
        entries: [DailyPlanEntry],
        titlesByReminderID: [String: String],
        executionStatesByReminderID: [String: TaskExecutionState] = [:],
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
                isMainObjective: entry.isMainObjective,
                executionState: executionStatesByReminderID[entry.reminderID]
            )
        }.sorted { $0.rank < $1.rank }
        self.availableMinutes = availableMinutes
        self.fixedCommitmentMinutes = fixedCommitmentMinutes
        self.usesCalendarAvailability = usesCalendarAvailability
        reviewedAvailabilityRevision = availabilityRevision
        queueRequestedAt = nil
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
            approvedAt: receipt?.approvedAt ?? approvedAt
        )
    }

    mutating func markReconciling(approvedAt: Date = Date()) {
        writeState = .reconciling
        receipt = CalendarPlanApprovalReceipt(
            items: items,
            availableMinutes: availableMinutes,
            fixedCommitmentMinutes: fixedCommitmentMinutes,
            usesCalendarAvailability: usesCalendarAvailability,
            commandIDs: [],
            outcome: .reconciling,
            commandCount: 0,
            approvedAt: approvedAt
        )
    }

    mutating func returnToReviewAfterAuthoritativeRefusal() {
        writeState = .reviewing
        receipt = nil
    }

    @discardableResult
    mutating func acceptLocally(approvedAt: Date = Date()) -> Bool {
        guard case .reviewing = writeState,
              !usesCalendarAvailability,
              !items.isEmpty
        else { return false }
        writeState = .applied(commandCount: 0)
        receipt = CalendarPlanApprovalReceipt(
            items: items,
            availableMinutes: availableMinutes,
            fixedCommitmentMinutes: fixedCommitmentMinutes,
            usesCalendarAvailability: false,
            commandIDs: [],
            outcome: .applied,
            commandCount: 0,
            approvedAt: approvedAt
        )
        return true
    }

    mutating func reconcile(with audit: [ActionAuditEntry]) {
        if receipt == nil,
           case .queueing = writeState,
           let queueRequestedAt {
            let reviewedTaskIDs = Set(items.map(\.reminderID))
            let scheduleActionTypes: Set<String> = [
                ActionCommandType.reconcileCalendarBlock.rawValue,
                ActionCommandType.scheduleNotification.rawValue,
                ActionCommandType.setReminderPriority.rawValue,
                ActionCommandType.setReminderDueDate.rawValue
            ]
            let committed = audit.filter {
                $0.createdAt >= queueRequestedAt
                    && reviewedTaskIDs.contains($0.entityID)
                    && scheduleActionTypes.contains($0.actionType)
            }
            let requiredTaskActionTypes: Set<String> = [
                ActionCommandType.reconcileCalendarBlock.rawValue,
                ActionCommandType.scheduleNotification.rawValue,
                ActionCommandType.setReminderPriority.rawValue
            ]
            let hasCompleteTaskCommandSet = reviewedTaskIDs.allSatisfy { taskID in
                let taskActionTypes = Set(committed.lazy.filter { $0.entityID == taskID }.map(\.actionType))
                return requiredTaskActionTypes.isSubset(of: taskActionTypes)
            }
            if hasCompleteTaskCommandSet, !committed.isEmpty {
                queued(
                    commandIDs: Array(Set(committed.map(\.id))).sorted(),
                    approvedAt: queueRequestedAt
                )
            }
        }
        guard case let .pending(commandIDs) = writeState else { return }
        let relevant = audit.filter { commandIDs.contains($0.id) }
        guard relevant.count == commandIDs.count else { return }
        let isFinal: (ActionAuditEntry) -> Bool = {
            $0.state == ActionCommandState.succeeded.rawValue
                || $0.state == ActionCommandState.terminalFailure.rawValue
                || $0.state == ActionCommandState.cancelled.rawValue
        }
        guard relevant.allSatisfy(isFinal) else { return }
        let completedBeforeCurrentAttempt = max(
            0,
            (receipt?.commandCount ?? commandIDs.count) - commandIDs.count
        )
        let failed = relevant.filter {
            $0.state == ActionCommandState.terminalFailure.rawValue
                || $0.state == ActionCommandState.cancelled.rawValue
        }
        if !failed.isEmpty {
            let failedCommandIDs = Set(failed.map(\.id))
            let totalCommandCount = completedBeforeCurrentAttempt + relevant.count
            writeState = .failed(commandIDs: failedCommandIDs)
            updateReceipt(
                outcome: .failed,
                commandIDs: failedCommandIDs,
                commandCount: totalCommandCount
            )
        } else if relevant.allSatisfy({ $0.state == ActionCommandState.succeeded.rawValue }) {
            let totalCommandCount = completedBeforeCurrentAttempt + relevant.count
            writeState = .applied(commandCount: totalCommandCount)
            updateReceipt(
                outcome: .applied,
                commandIDs: commandIDs,
                commandCount: totalCommandCount
            )
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
        updateReceipt(
            outcome: .pending,
            commandIDs: commandIDs,
            commandCount: max(receipt?.commandCount ?? 0, commandIDs.count)
        )
        return commandIDs.sorted()
    }

    mutating func retryRequestFailed(commandIDs: [String]) {
        let identifiers = Set(commandIDs)
        writeState = .failed(commandIDs: identifiers)
        updateReceipt(
            outcome: .failed,
            commandIDs: identifiers,
            commandCount: max(receipt?.commandCount ?? 0, identifiers.count)
        )
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
        case .reconciling:
            writeState = .reconciling
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
