import Foundation

public enum ReminderCompletionSyncPhase: String, Codable, Equatable, Sendable {
    case notRequested
    case pending
    case retrying
    case failed
    case unavailable
    case confirmed
}

public struct ReminderCompletionSyncState: Codable, Equatable, Sendable {
    public let taskID: String
    public let taskTitle: String?
    public let commandID: String?
    public let phase: ReminderCompletionSyncPhase
    public let attemptCount: Int
    public let updatedAt: Date?

    public init(taskID: String, audit: [ActionAuditEntry]) {
        self.taskID = taskID
        taskTitle = nil
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

    public init(taskID: String, command: ActionCommand?, taskTitle: String? = nil) {
        self.taskID = taskID
        self.taskTitle = taskTitle
        commandID = command?.id
        attemptCount = command?.attemptCount ?? 0
        updatedAt = command?.updatedAt
        switch command?.state {
        case .pending: phase = .pending
        case .executing: phase = .retrying
        case .retryableFailure, .terminalFailure: phase = .failed
        case .cancelled: phase = .unavailable
        case .succeeded: phase = .confirmed
        case nil: phase = .notRequested
        }
    }

    public var isAwaitingConfirmation: Bool {
        phase == .pending || phase == .retrying
    }

    public var canRetry: Bool { phase == .failed && commandID != nil }

    public var userFacingDetail: String? {
        return switch phase {
        case .notRequested: nil
        case .pending: "Completion is waiting for Apple Reminders. The task and its history stay here until sync finishes."
        case .retrying: "Apple Reminders sync is being tried now."
        case .failed: "Apple Reminders did not confirm completion. Your local task and history are safe. Repair Reminders access, then retry."
        case .unavailable: "Apple Reminders completion was not issued in the current operating mode. Your local task and history are safe."
        case .confirmed: "Completion confirmed by Apple Reminders."
        }
    }

    public func detail(localExecutionIsCompleted: Bool) -> String? {
        if localExecutionIsCompleted, phase == .notRequested {
            return "Local completion is saved, but Apple Reminders confirmation is unavailable. Refresh source status before treating it as synchronized."
        }
        return userFacingDetail
    }

    public func statusLabel(localExecutionIsCompleted: Bool) -> String? {
        guard localExecutionIsCompleted else { return nil }
        return switch phase {
        case .notRequested: "Completion sync unknown"
        case .pending, .retrying, .failed, .unavailable: "Completion pending Reminders"
        case .confirmed: "Completed"
        }
    }
}
