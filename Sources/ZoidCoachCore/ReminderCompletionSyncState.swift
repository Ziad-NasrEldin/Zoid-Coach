import Foundation

public enum ReminderCompletionSyncPhase: String, Equatable, Sendable {
    case notRequested
    case pending
    case retrying
    case failed
    case unavailable
    case confirmed
}

public struct ReminderCompletionSyncState: Equatable, Sendable {
    public let taskID: String
    public let commandID: String?
    public let phase: ReminderCompletionSyncPhase
    public let attemptCount: Int
    public let updatedAt: Date?

    public init(taskID: String, audit: [ActionAuditEntry]) {
        self.taskID = taskID
        guard let latest = audit
            .filter({ $0.actionType == ActionCommandType.completeReminder.rawValue && $0.entityID == taskID })
            .max(by: { lhs, rhs in
                if lhs.updatedAt == rhs.updatedAt { return lhs.createdAt < rhs.createdAt }
                return lhs.updatedAt < rhs.updatedAt
            })
        else {
            commandID = nil
            phase = .notRequested
            attemptCount = 0
            updatedAt = nil
            return
        }

        commandID = latest.id
        attemptCount = latest.attemptCount
        updatedAt = latest.updatedAt
        switch latest.state {
        case "pending": phase = .pending
        case "executing": phase = .retrying
        case "retryable_failure", "terminal_failure": phase = .failed
        case "cancelled": phase = .unavailable
        case "succeeded": phase = .confirmed
        default: phase = .notRequested
        }
    }

    public var isAwaitingConfirmation: Bool {
        phase == .pending || phase == .retrying
    }

    public var canRetry: Bool { phase == .failed && commandID != nil }

    public var userFacingDetail: String? {
        switch phase {
        case .notRequested: nil
        case .pending: "Completion is waiting for Apple Reminders. The task and its history stay here until sync finishes."
        case .retrying: "Apple Reminders sync is being tried now."
        case .failed: "Apple Reminders did not confirm completion. Your local task and history are safe. Repair Reminders access, then retry."
        case .unavailable: "Apple Reminders completion was not issued in the current operating mode. Your local task and history are safe."
        case .confirmed: "Completion confirmed by Apple Reminders."
        }
    }
}
