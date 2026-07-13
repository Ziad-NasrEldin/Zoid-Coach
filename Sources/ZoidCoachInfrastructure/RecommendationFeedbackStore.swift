import Foundation
import ZoidCoachCore

public final class RecommendationFeedbackStore: @unchecked Sendable {
    public static let eventType = "recommendation_feedback"
    public static let notNowSuppression: TimeInterval = 30 * 60

    private let events: DomainEventStore

    public init(databaseURL: URL = ZoidCoachStorage.databaseURL()) throws {
        events = try DomainEventStore(databaseURL: databaseURL)
    }

    @discardableResult
    public func record(
        _ request: RecommendationFeedbackRequest,
        timeZoneIdentifier: String
    ) throws -> RecommendationFeedbackRecord {
        let taskID = request.taskID.trimmingCharacters(in: .whitespacesAndNewlines)
        let sentence = request.recommendationSentence.trimmingCharacters(in: .whitespacesAndNewlines)
        guard request.requestID.hasPrefix("recommendation-feedback-v1:"),
              request.requestID.count <= 180,
              !taskID.isEmpty,
              taskID.count <= 256,
              !sentence.isEmpty,
              sentence.count <= 500,
              TimeZone(identifier: timeZoneIdentifier) != nil else {
            throw RecommendationFeedbackStoreError.invalidFeedback
        }

        let localDay = Self.localDay(request.occurredAt, timeZoneIdentifier: timeZoneIdentifier)
        if let existing = try events.events(localDay: localDay, limit: 500)
            .first(where: { $0.id == request.requestID }) {
            guard existing.type == Self.eventType,
                  existing.entityID == taskID,
                  existing.payload["kind"] == request.kind.rawValue,
                  existing.payload["recommendation"] == sentence else {
                throw RecommendationFeedbackStoreError.idempotencyConflict
            }
            return RecommendationFeedbackRecord(
                requestID: existing.id,
                taskID: taskID,
                kind: request.kind,
                localDay: existing.localDay,
                occurredAt: existing.occurredAt
            )
        }
        try events.append(DomainEvent(
            id: request.requestID,
            type: Self.eventType,
            entityID: taskID,
            localDay: localDay,
            timezoneIdentifier: timeZoneIdentifier,
            occurredAt: request.occurredAt,
            schemaVersion: 1,
            evidenceIDs: [],
            payload: [
                "kind": request.kind.rawValue,
                "recommendation": sentence
            ]
        ))
        return RecommendationFeedbackRecord(
            requestID: request.requestID,
            taskID: taskID,
            kind: request.kind,
            localDay: localDay,
            occurredAt: request.occurredAt
        )
    }

    public func suppressedTaskIDs(
        at date: Date,
        timeZoneIdentifier: String
    ) throws -> Set<String> {
        let localDay = Self.localDay(date, timeZoneIdentifier: timeZoneIdentifier)
        return Set(try records(localDay: localDay).compactMap { record in
            switch record.kind {
            case .notNow:
                date.timeIntervalSince(record.occurredAt) < Self.notNowSuppression
                    ? record.taskID
                    : nil
            case .wrongPriority, .tooLarge:
                record.taskID
            }
        })
    }

    public func records(localDay: String) throws -> [RecommendationFeedbackRecord] {
        try events.events(localDay: localDay, limit: 500).compactMap { event in
            guard event.type == Self.eventType,
                  let taskID = event.entityID,
                  let rawKind = event.payload["kind"],
                  let kind = RecommendationFeedbackKind(rawValue: rawKind) else {
                return nil
            }
            return RecommendationFeedbackRecord(
                requestID: event.id,
                taskID: taskID,
                kind: kind,
                localDay: event.localDay,
                occurredAt: event.occurredAt
            )
        }
    }

    private static func localDay(_ date: Date, timeZoneIdentifier: String) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: timeZoneIdentifier) ?? .current
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
    }
}

public enum RecommendationFeedbackStoreError: LocalizedError {
    case invalidFeedback
    case idempotencyConflict

    public var errorDescription: String? {
        switch self {
        case .invalidFeedback:
            "The recommendation feedback was invalid and was not saved."
        case .idempotencyConflict:
            "This recommendation feedback request was already used for a different choice."
        }
    }
}
