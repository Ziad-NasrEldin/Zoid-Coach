import Foundation

public struct SourceTask: Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let listIdentifier: String
    public let priority: Int
    public let dueDate: Date?
    public let notes: String?
    public let metadataMarker: String?
    public let isCompleted: Bool

    public init(
        id: String,
        title: String,
        listIdentifier: String,
        priority: Int,
        dueDate: Date?,
        notes: String?,
        metadataMarker: String? = nil,
        isCompleted: Bool
    ) {
        self.id = id
        self.title = title
        self.listIdentifier = listIdentifier
        self.priority = priority
        self.dueDate = dueDate
        self.notes = notes
        self.metadataMarker = metadataMarker
        self.isCompleted = isCompleted
    }
}

public enum TaskSourceMutation: Equatable, Sendable {
    case setPriority(Int)
    case setDueDate(Date?)
    case setMetadataMarker(String?)
    case complete(at: Date)
}

public protocol TaskSource: Sendable {
    func task(identifier: String) async throws -> SourceTask?
    func task(metadataMarker: String) async throws -> SourceTask?
    func create(title: String, dueDate: Date?, listIdentifier: String?, metadataMarker: String?) async throws -> SourceTask
    func apply(_ mutation: TaskSourceMutation, to identifier: String) async throws -> SourceTask
}

public extension TaskSource {
    func task(metadataMarker: String) async throws -> SourceTask? { nil }
}

public struct CalendarCommitment: Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let start: Date
    public let end: Date
    public let calendarIdentifier: String
    public let ownershipToken: String?
    public let meetingFingerprint: String?

    public init(
        id: String,
        title: String,
        start: Date,
        end: Date,
        calendarIdentifier: String,
        ownershipToken: String? = nil,
        meetingFingerprint: String? = nil
    ) {
        self.id = id
        self.title = title
        self.start = start
        self.end = end
        self.calendarIdentifier = calendarIdentifier
        self.ownershipToken = ownershipToken
        self.meetingFingerprint = meetingFingerprint
    }
}

public struct CalendarBlockMutation: Equatable, Sendable {
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

public struct ConfirmedMeetingMutation: Equatable, Sendable {
    public let title: String
    public let start: Date
    public let end: Date
    public let calendarIdentifier: String?
    public let fingerprint: String
    public let participants: [String]
    public let location: String?
    public let callLink: String?
    public let timezoneIdentifier: String?

    public init(
        title: String,
        start: Date,
        end: Date,
        calendarIdentifier: String?,
        fingerprint: String,
        participants: [String] = [],
        location: String? = nil,
        callLink: String? = nil,
        timezoneIdentifier: String? = nil
    ) {
        self.title = title
        self.start = start
        self.end = end
        self.calendarIdentifier = calendarIdentifier
        self.fingerprint = fingerprint
        self.participants = participants
        self.location = location
        self.callLink = callLink
        self.timezoneIdentifier = timezoneIdentifier
    }
}

public enum CalendarSourceMutation: Equatable, Sendable {
    case createBlock(CalendarBlockMutation)
    case updateOwnedBlock(identifier: String, CalendarBlockMutation)
    case deleteOwnedBlock(identifier: String, ownershipToken: String)
    case createConfirmedMeeting(ConfirmedMeetingMutation)
}

public protocol CalendarSource: Sendable {
    func commitment(identifier: String) async throws -> CalendarCommitment?
    func ownedCommitment(ownershipToken: String) async throws -> CalendarCommitment?
    func confirmedMeeting(fingerprint: String) async throws -> CalendarCommitment?
    func apply(_ mutation: CalendarSourceMutation) async throws -> CalendarCommitment?
}

public protocol CalendarAvailabilitySource: Sendable {
    func commitments(from start: Date, through end: Date, calendarIdentifiers: [String]) async throws -> [CalendarCommitment]
}

public protocol NotificationSource: Sendable {
    func pending(identifier: String) async throws -> Bool
    func schedule(_ desired: NotificationDesiredState) async throws -> String
}

public struct UnavailableNotificationSource: NotificationSource {
    public init() {}
    public func pending(identifier: String) async throws -> Bool { false }
    public func schedule(_ desired: NotificationDesiredState) async throws -> String {
        throw ActionSourceError.unsupported
    }
}

public enum ActionSourceError: Error, Equatable, Sendable {
    case accessDenied
    case temporarilyUnavailable
    case missingEntity
    case ownershipViolation
    case invalidDesiredState
    case unsupported
}
