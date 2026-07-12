import Foundation
import ZoidCoachCore

struct CalendarPlanApprovalItem: Equatable, Identifiable, Sendable {
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

struct CalendarPlanApprovalState: Equatable, Sendable {
    var items: [CalendarPlanApprovalItem] = []
    var availableMinutes = 0
    var fixedCommitmentMinutes = 0
    var usesCalendarAvailability = false
    var writeState: CalendarPlanWriteState = .idle

    var isPresented: Bool { writeState != .idle }
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
    }

    mutating func queued(commandIDs: [String]) {
        let identifiers = Set(commandIDs)
        writeState = identifiers.isEmpty ? .applied(commandCount: 0) : .pending(commandIDs: identifiers)
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
        } else if relevant.allSatisfy({ $0.state == ActionCommandState.succeeded.rawValue }) {
            writeState = .applied(commandCount: relevant.count)
        }
    }

    mutating func dismiss() {
        self = .init()
    }
}
