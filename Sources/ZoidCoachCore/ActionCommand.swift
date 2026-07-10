import CryptoKit
import Foundation

public enum ActionCommandType: String, Codable, CaseIterable, Sendable {
    case createCalendarBlock
    case updateCalendarBlock
    case reconcileCalendarBlock
    case deleteCalendarBlock
    case setReminderPriority
    case setReminderDueDate
    case setReminderMetadata
    case completeReminder
    case createReminder
    case createConfirmedMeeting
    case scheduleNotification
}

public enum ActionCommandState: String, Codable, Sendable {
    case pending
    case executing
    case succeeded
    case retryableFailure = "retryable_failure"
    case terminalFailure = "terminal_failure"
    case cancelled
}

public enum ActionOrigin: String, Codable, Sendable {
    case automaticPlan = "automatic_plan"
    case approvedPlan = "approved_plan"
    case explicitUser = "explicit_user"
}

public struct CalendarBlockDesiredState: Equatable, Codable, Sendable {
    public let title: String
    public let start: Date
    public let end: Date
    public let ownershipToken: String
    public let planItemID: String

    public init(title: String, start: Date, end: Date, ownershipToken: String, planItemID: String) {
        self.title = title
        self.start = start
        self.end = end
        self.ownershipToken = ownershipToken
        self.planItemID = planItemID
    }
}

public struct ReminderDesiredState: Equatable, Codable, Sendable {
    public let priority: Int?
    public let dueDate: Date?
    public let shouldClearDueDate: Bool
    public let metadataMarker: String?

    public init(priority: Int? = nil, dueDate: Date? = nil, shouldClearDueDate: Bool = false, metadataMarker: String? = nil) {
        self.priority = priority
        self.dueDate = dueDate
        self.shouldClearDueDate = shouldClearDueDate
        self.metadataMarker = metadataMarker
    }
}

public struct ReminderCreationDesiredState: Equatable, Codable, Sendable {
    public let title: String
    public let dueDate: Date?
    public let listIdentifier: String?
    public let metadataMarker: String?

    public init(title: String, dueDate: Date?, listIdentifier: String? = nil, metadataMarker: String? = nil) {
        self.title = title
        self.dueDate = dueDate
        self.listIdentifier = listIdentifier
        self.metadataMarker = metadataMarker
    }
}

public struct MeetingDesiredState: Equatable, Codable, Sendable {
    public let title: String
    public let start: Date
    public let durationMinutes: Int
    public let calendarIdentifier: String?
    public let candidateFingerprint: String
    public let participants: [String]
    public let location: String?
    public let callLink: String?
    public let timezoneIdentifier: String?

    public init(
        title: String,
        start: Date,
        durationMinutes: Int,
        calendarIdentifier: String?,
        candidateFingerprint: String,
        participants: [String] = [],
        location: String? = nil,
        callLink: String? = nil,
        timezoneIdentifier: String? = nil
    ) {
        self.title = title
        self.start = start
        self.durationMinutes = max(1, durationMinutes)
        self.calendarIdentifier = calendarIdentifier
        self.candidateFingerprint = candidateFingerprint
        self.participants = participants
        self.location = location
        self.callLink = callLink
        self.timezoneIdentifier = timezoneIdentifier
    }

    private enum CodingKeys: String, CodingKey {
        case title, start, durationMinutes, calendarIdentifier, candidateFingerprint
        case participants, location, callLink, timezoneIdentifier
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            title: try container.decode(String.self, forKey: .title),
            start: try container.decode(Date.self, forKey: .start),
            durationMinutes: try container.decode(Int.self, forKey: .durationMinutes),
            calendarIdentifier: try container.decodeIfPresent(String.self, forKey: .calendarIdentifier),
            candidateFingerprint: try container.decode(String.self, forKey: .candidateFingerprint),
            participants: try container.decodeIfPresent([String].self, forKey: .participants) ?? [],
            location: try container.decodeIfPresent(String.self, forKey: .location),
            callLink: try container.decodeIfPresent(String.self, forKey: .callLink),
            timezoneIdentifier: try container.decodeIfPresent(String.self, forKey: .timezoneIdentifier)
        )
    }
}

public struct NotificationDesiredState: Equatable, Codable, Sendable {
    public let category: String
    public let title: String
    public let body: String
    public let promptID: String
    public let deliveryDate: Date?

    public init(category: String, title: String, body: String, promptID: String, deliveryDate: Date? = nil) {
        self.category = category
        self.title = title
        self.body = body
        self.promptID = promptID
        self.deliveryDate = deliveryDate
    }
}

public enum ActionDesiredState: Equatable, Codable, Sendable {
    case calendarBlock(CalendarBlockDesiredState)
    case reminder(ReminderDesiredState)
    case meeting(MeetingDesiredState)
    case notification(NotificationDesiredState)
    case deleteOwnedCalendarBlock(ownershipToken: String)
    case completeReminder
    case createReminder(ReminderCreationDesiredState)
}

public struct ActionCommand: Identifiable, Equatable, Codable, Sendable {
    public let id: String
    public let idempotencyKey: String
    public let type: ActionCommandType
    public let entityID: String
    public let desiredState: ActionDesiredState
    public let state: ActionCommandState
    public let attemptCount: Int
    public let nextAttemptAt: Date?
    public let createdAt: Date
    public let updatedAt: Date

    public init(id: String, idempotencyKey: String, type: ActionCommandType, entityID: String, desiredState: ActionDesiredState, state: ActionCommandState = .pending, attemptCount: Int = 0, nextAttemptAt: Date? = nil, createdAt: Date, updatedAt: Date) {
        self.id = id
        self.idempotencyKey = idempotencyKey
        self.type = type
        self.entityID = entityID
        self.desiredState = desiredState
        self.state = state
        self.attemptCount = attemptCount
        self.nextAttemptAt = nextAttemptAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public struct ActionAttempt: Identifiable, Equatable, Codable, Sendable {
    public let id: String
    public let commandID: String
    public let attemptNumber: Int
    public let state: ActionCommandState
    public let platformIdentifier: String?
    public let redactedError: String?
    public let startedAt: Date
    public let finishedAt: Date?

    public init(id: String, commandID: String, attemptNumber: Int, state: ActionCommandState, platformIdentifier: String?, redactedError: String?, startedAt: Date, finishedAt: Date?) {
        self.id = id
        self.commandID = commandID
        self.attemptNumber = attemptNumber
        self.state = state
        self.platformIdentifier = platformIdentifier
        self.redactedError = redactedError
        self.startedAt = startedAt
        self.finishedAt = finishedAt
    }
}

public enum ActionIdempotencyKey {
    public static func make(
        type: ActionCommandType,
        entityID: String,
        desiredState: ActionDesiredState,
        planVersion: Int,
        origin: ActionOrigin = .explicitUser
    ) throws -> String {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let payload = try encoder.encode(desiredState)
        var input = Data(type.rawValue.utf8)
        input.append(0)
        input.append(Data(entityID.utf8))
        input.append(0)
        input.append(Data(String(planVersion).utf8))
        input.append(0)
        input.append(Data(origin.rawValue.utf8))
        input.append(0)
        input.append(payload)
        return SHA256.hash(data: input).map { String(format: "%02x", $0) }.joined()
    }
}
