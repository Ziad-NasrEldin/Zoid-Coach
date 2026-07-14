import CryptoKit
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
    public let estimateIsUncertain: Bool?
    public let selectionReason: String?
    public let selectionScore: Int?
    public let isOptional: Bool?
    public let blockedReason: String?
    public let deferredUntil: Date?

    public init(
        reminderID: String,
        rank: Int,
        isMainObjective: Bool,
        estimateMinutes: Int?,
        estimateIsUncertain: Bool = false,
        selectionReason: String?,
        selectionScore: Int?,
        isOptional: Bool = false,
        blockedReason: String? = nil,
        deferredUntil: Date? = nil
    ) {
        self.reminderID = reminderID
        self.rank = rank
        self.isMainObjective = isMainObjective
        self.estimateMinutes = estimateMinutes
        self.estimateIsUncertain = estimateIsUncertain
        self.selectionReason = selectionReason
        self.selectionScore = selectionScore
        self.isOptional = isOptional
        self.blockedReason = blockedReason
        self.deferredUntil = deferredUntil
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

public struct AgentLocalTask: Equatable, Codable, Sendable {
    public let id: String
    public let title: String
    public let notes: String?
    public let estimateMinutes: Int

    public init(id: String, title: String, notes: String?, estimateMinutes: Int) {
        self.id = id
        self.title = title
        self.notes = notes
        self.estimateMinutes = estimateMinutes
    }
}

public enum PolicyMutationOrigin: Equatable, Codable, Sendable {
    case settings
    case onboarding(flowID: String, step: OnboardingStep, progressRevision: UInt64)
    case system(component: String)
}

public struct PolicyMutationRequest: Equatable, Codable, Sendable {
    public let requestID: String
    public let expectedVersion: Int
    public let policy: UserPolicy
    public let origin: PolicyMutationOrigin

    public init(
        requestID: String,
        expectedVersion: Int,
        policy: UserPolicy,
        origin: PolicyMutationOrigin
    ) {
        self.requestID = requestID
        self.expectedVersion = expectedVersion
        self.policy = policy
        self.origin = origin
    }

    public static func canonicalPayloadDigest(for policy: UserPolicy) throws -> String {
        let data = try JSONEncoder.zoidPolicy.encode(
            policy.canonicalizedForPolicyMutationDigest()
        )
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

public struct PolicyMutationReceipt: Equatable, Codable, Sendable {
    public let requestID: String
    public let payloadDigest: String
    public let expectedVersion: Int
    public let resultingVersion: Int
    public let origin: PolicyMutationOrigin
    public let replayed: Bool

    public init(
        requestID: String,
        payloadDigest: String,
        expectedVersion: Int,
        resultingVersion: Int,
        origin: PolicyMutationOrigin,
        replayed: Bool
    ) {
        self.requestID = requestID
        self.payloadDigest = payloadDigest
        self.expectedVersion = expectedVersion
        self.resultingVersion = resultingVersion
        self.origin = origin
        self.replayed = replayed
    }
}

public enum AgentMutationCommand: Equatable, Codable, Sendable {
    case completeReminder(reminderID: String)
    case rescheduleReminder(reminderID: String, dueDate: Date)
    case createLocalTask(task: AgentLocalTask, addToToday: Bool, day: Date)
    case replaceDailyPlan(items: [AgentPlanItem], day: Date)
    case replaceReminderListOrder([String])
    case recordTaskHistory(taskID: String, state: AgentTaskHistoryState, occurredAt: Date)
    case recordRecommendationFeedback(RecommendationFeedbackRequest)
    case recordSourceCheck(sourceID: String, state: String, detail: String, evidence: String, checkedAt: Date)
    case synchronizeReminderSnapshots([AgentReminderSnapshot])
    case savePolicyMutation(PolicyMutationRequest)
    case undoAction(commandID: String)
    case exportRedactedDiagnostics
    case exportRedactedDiagnosticsTo(path: String)
    case deleteDataRange(start: Date, end: Date)
    case deleteBehaviorSession(application: String, startedAt: Date, endedAt: Date)
    case deleteExtractedConversationText
    case deleteRawBehaviorMetadata
    case deleteAIRequestMetadata
    case deleteReviewsAndLearnedRules
    case deleteAllUserData
    case draftPlan(day: Date, overwriteExisting: Bool)
    case schedulePlan(day: Date, operationID: UUID)
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
    public let policyMutationReceipt: PolicyMutationReceipt?

    public init(accepted: Bool, commandIDs: [String] = [], message: String, policyVersion: Int? = nil, artifactPath: String? = nil, policyMutationReceipt: PolicyMutationReceipt? = nil) {
        self.accepted = accepted
        self.commandIDs = commandIDs
        self.message = message
        self.policyVersion = policyVersion
        self.artifactPath = artifactPath
        self.policyMutationReceipt = policyMutationReceipt
    }
}
