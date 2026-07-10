import Foundation

public enum AgentMeetingDestination: String, Codable, Sendable {
    case calendar
    case reminder
}

public struct AgentPlanItem: Equatable, Codable, Sendable {
    public let reminderID: String
    public let rank: Int
    public let isMainObjective: Bool
    public let estimateMinutes: Int?
    public let selectionReason: String?
    public let selectionScore: Int?

    public init(reminderID: String, rank: Int, isMainObjective: Bool, estimateMinutes: Int?, selectionReason: String?, selectionScore: Int?) {
        self.reminderID = reminderID
        self.rank = rank
        self.isMainObjective = isMainObjective
        self.estimateMinutes = estimateMinutes
        self.selectionReason = selectionReason
        self.selectionScore = selectionScore
    }
}

public enum AgentTaskHistoryState: String, Codable, Sendable {
    case selected
    case completed
    case postponed
}

public struct AgentReminderSnapshot: Equatable, Codable, Sendable {
    public let id: String
    public let title: String
    public let dueDate: Date?
    public let priority: Int
    public let notes: String?
    public let listID: String?
    public let listName: String?
    public let modificationDate: Date?
    public let isCompleted: Bool

    public init(id: String, title: String, dueDate: Date?, priority: Int, notes: String?, listID: String?, listName: String?, modificationDate: Date?, isCompleted: Bool = false) {
        self.id = id
        self.title = title
        self.dueDate = dueDate
        self.priority = priority
        self.notes = notes
        self.listID = listID
        self.listName = listName
        self.modificationDate = modificationDate
        self.isCompleted = isCompleted
    }
}

public enum AgentMutationCommand: Equatable, Codable, Sendable {
    case completeReminder(reminderID: String)
    case replaceDailyPlan(items: [AgentPlanItem], day: Date)
    case replaceReminderListOrder([String])
    case recordTaskHistory(taskID: String, state: AgentTaskHistoryState, occurredAt: Date)
    case recordSourceCheck(sourceID: String, state: String, detail: String, evidence: String, checkedAt: Date)
    case synchronizeReminderSnapshots([AgentReminderSnapshot])
    case savePolicy(UserPolicy)
    case undoAction(commandID: String)
    case exportRedactedDiagnostics
    case deleteDataRange(start: Date, end: Date)
    case deleteExtractedConversationText
    case draftPlan(day: Date, overwriteExisting: Bool)
    case schedulePlan(day: Date)
    case resolveMeetingCandidate(
        candidateID: String,
        title: String,
        start: Date,
        durationMinutes: Int,
        destination: AgentMeetingDestination
    )
    case ignoreMeetingCandidate(candidateID: String)
    case deferMeetingCandidate(candidateID: String)
}

public struct ActionAuditEntry: Identifiable, Equatable, Codable, Sendable {
    public let id: String
    public let actionType: String
    public let entityID: String
    public let state: String
    public let attemptCount: Int
    public let createdAt: Date
    public let updatedAt: Date
    public let canUndo: Bool

    public init(id: String, actionType: String, entityID: String, state: String, attemptCount: Int, createdAt: Date, updatedAt: Date, canUndo: Bool) {
        self.id = id
        self.actionType = actionType
        self.entityID = entityID
        self.state = state
        self.attemptCount = attemptCount
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.canUndo = canUndo
    }
}

public struct AgentMutationReceipt: Equatable, Codable, Sendable {
    public let accepted: Bool
    public let commandIDs: [String]
    public let message: String
    public let policyVersion: Int?
    public let artifactPath: String?

    public init(accepted: Bool, commandIDs: [String] = [], message: String, policyVersion: Int? = nil, artifactPath: String? = nil) {
        self.accepted = accepted
        self.commandIDs = commandIDs
        self.message = message
        self.policyVersion = policyVersion
        self.artifactPath = artifactPath
    }
}
