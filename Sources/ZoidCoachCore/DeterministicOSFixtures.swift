import Foundation

public enum QAFixturePermission: String, Codable, CaseIterable, Sendable {
    case reminders
    case calendar
    case notifications
}

public enum QAFixturePermissionState: String, Codable, CaseIterable, Sendable {
    case granted
    case denied
    case restricted
    case notDetermined
}

public enum QAFixtureEntityKind: String, Codable, Sendable {
    case reminder
    case calendarCommitment
    case notification
    case audit
}

public enum QAFixtureNotificationStatus: String, Codable, Sendable {
    case scheduled
    case delivered
    case responded
}

public struct QAFixtureNotificationRecord: Equatable, Codable, Sendable {
    public let id: String
    public let desired: NotificationDesiredState
    public let status: QAFixtureNotificationStatus
    public let deliveredAt: Date?
    public let actionIdentifier: String?
    public let respondedAt: Date?

    public init(
        id: String,
        desired: NotificationDesiredState,
        status: QAFixtureNotificationStatus = .scheduled,
        deliveredAt: Date? = nil,
        actionIdentifier: String? = nil,
        respondedAt: Date? = nil
    ) {
        self.id = id
        self.desired = desired
        self.status = status
        self.deliveredAt = deliveredAt
        self.actionIdentifier = actionIdentifier
        self.respondedAt = respondedAt
    }
}

public struct QAFixtureOperationAuditEntry: Equatable, Codable, Sendable {
    public let id: String
    public let timestamp: Date
    public let subsystem: String
    public let operation: String
    public let targetID: String?
    public let outcome: String

    public init(
        id: String,
        timestamp: Date,
        subsystem: String,
        operation: String,
        targetID: String?,
        outcome: String
    ) {
        self.id = id
        self.timestamp = timestamp
        self.subsystem = subsystem
        self.operation = operation
        self.targetID = targetID
        self.outcome = outcome
    }
}

public struct QAFixtureOSSeed: Equatable, Codable, Sendable {
    public let permissions: [QAFixturePermission: QAFixturePermissionState]
    public let reminderLists: [QAFixtureReminderList]
    public let reminders: [SourceTask]
    public let calendarCommitments: [CalendarCommitment]
    public let notifications: [QAFixtureNotificationRecord]
    public let notificationSchedulingFailure: String?

    public init(
        permissions: [QAFixturePermission: QAFixturePermissionState] = [:],
        reminderLists: [QAFixtureReminderList] = [],
        reminders: [SourceTask] = [],
        calendarCommitments: [CalendarCommitment] = [],
        notifications: [QAFixtureNotificationRecord] = [],
        notificationSchedulingFailure: String? = nil
    ) {
        self.permissions = permissions
        self.reminderLists = reminderLists
        self.reminders = reminders
        self.calendarCommitments = calendarCommitments
        self.notifications = notifications
        self.notificationSchedulingFailure = notificationSchedulingFailure
    }
}

public struct QAFixtureReminderList: Identifiable, Equatable, Codable, Sendable {
    public let id: String
    public let name: String

    public init(id: String, name: String) {
        self.id = id
        self.name = name
    }
}

public struct QAFixtureOSSnapshot: Equatable, Codable, Sendable {
    public let permissions: [QAFixturePermission: QAFixturePermissionState]
    public let reminderLists: [QAFixtureReminderList]
    public let reminders: [SourceTask]
    public let calendarCommitments: [CalendarCommitment]
    public let notifications: [QAFixtureNotificationRecord]
    public let audit: [QAFixtureOperationAuditEntry]

    public init(
        permissions: [QAFixturePermission: QAFixturePermissionState],
        reminderLists: [QAFixtureReminderList] = [],
        reminders: [SourceTask],
        calendarCommitments: [CalendarCommitment],
        notifications: [QAFixtureNotificationRecord],
        audit: [QAFixtureOperationAuditEntry]
    ) {
        self.permissions = permissions
        self.reminderLists = reminderLists
        self.reminders = reminders
        self.calendarCommitments = calendarCommitments
        self.notifications = notifications
        self.audit = audit
    }
}
