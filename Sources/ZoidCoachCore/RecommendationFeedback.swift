import Foundation

public enum RecommendationFeedbackKind: String, Codable, CaseIterable, Sendable {
    case notNow = "not_now"
    case wrongPriority = "wrong_priority"
    case tooLarge = "too_large"
    case hideToday = "hide_today"

    public var confirmationMessage: String {
        switch self {
        case .notNow:
            "Not now recorded. Zoid 666 will choose another ready task for the next 30 minutes."
        case .wrongPriority:
            "Wrong priority recorded. Zoid 666 will choose another ready task for today."
        case .tooLarge:
            "Too large recorded. Zoid 666 will choose another ready task for today."
        case .hideToday:
            "Hidden for today. Zoid 666 will choose another ready task until tomorrow."
        }
    }
}

public struct RecommendationFeedbackRequest: Equatable, Codable, Sendable {
    public let requestID: String
    public let taskID: String
    public let recommendationSentence: String
    public let kind: RecommendationFeedbackKind
    public let occurredAt: Date

    public init(
        requestID: String,
        taskID: String,
        recommendationSentence: String,
        kind: RecommendationFeedbackKind,
        occurredAt: Date = Date()
    ) {
        self.requestID = requestID
        self.taskID = taskID
        self.recommendationSentence = recommendationSentence
        self.kind = kind
        self.occurredAt = occurredAt
    }
}

public struct RecommendationFeedbackRecord: Equatable, Codable, Sendable {
    public let requestID: String
    public let taskID: String
    public let kind: RecommendationFeedbackKind
    public let localDay: String
    public let occurredAt: Date

    public init(
        requestID: String,
        taskID: String,
        kind: RecommendationFeedbackKind,
        localDay: String,
        occurredAt: Date
    ) {
        self.requestID = requestID
        self.taskID = taskID
        self.kind = kind
        self.localDay = localDay
        self.occurredAt = occurredAt
    }
}
