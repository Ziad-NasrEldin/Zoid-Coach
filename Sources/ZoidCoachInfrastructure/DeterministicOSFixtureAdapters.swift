import Foundation
import ZoidCoachCore

public enum QAFixtureStateError: Error, Equatable, Sendable {
    case qaWorkspaceRequired
    case stateOutsideWorkspace(path: String)
    case corruptState(path: String)
    case duplicateIdentifier(String)
    case emptyStableIdentifier
}

public enum QAFixtureCorruptionRecovery: Sendable {
    case fail
    case reset(QAFixtureOSSeed)
}

public final class DeterministicOSFixtureAdapters: TaskSource, CalendarSource,
    CalendarAvailabilitySource, NotificationSource, @unchecked Sendable {
    public typealias StableIDProvider = @Sendable (QAFixtureEntityKind, Int) -> String

    private struct PersistedState: Codable {
        var schemaVersion = 1
        var permissions: [QAFixturePermission: QAFixturePermissionState]
        var reminders: [SourceTask]
        var calendarCommitments: [CalendarCommitment]
        var notifications: [QAFixtureNotificationRecord]
        var audit: [QAFixtureOperationAuditEntry]
        var counters: [QAFixtureEntityKind: Int]

        init(seed: QAFixtureOSSeed) {
            permissions = seed.permissions
            reminders = seed.reminders
            calendarCommitments = seed.calendarCommitments
            notifications = seed.notifications
            audit = []
            counters = [:]
        }
    }

    private let workspace: QAFixtureWorkspace
    private let clock: ZoidClock
    private let stableID: StableIDProvider
    private let fileManager: FileManager
    private let lock = NSLock()
    private var state: PersistedState
    public let stateFileURL: URL
    public let corruptStateFileURL: URL

    public init(
        workspace: QAFixtureWorkspace,
        seed: QAFixtureOSSeed = .init(),
        clock: ZoidClock,
        stableID: @escaping StableIDProvider,
        corruptionRecovery: QAFixtureCorruptionRecovery = .fail,
        fileManager: FileManager = .default
    ) throws {
        guard case let .qa(runRoot) = workspace.environment.mode,
              runRoot.standardizedFileURL == workspace.root.standardizedFileURL else {
            throw QAFixtureStateError.qaWorkspaceRequired
        }
        self.workspace = workspace
        self.clock = clock
        self.stableID = stableID
        self.fileManager = fileManager
        var recoveredCorruptState = false
        let directory = workspace.root.appendingPathComponent("OS Fixtures", isDirectory: true)
        stateFileURL = directory.appendingPathComponent("state.json")
        corruptStateFileURL = directory.appendingPathComponent("state.corrupt.json")
        try Self.validateContained(directory, in: workspace.root, fileManager: fileManager)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        try Self.validateContained(stateFileURL, in: workspace.root, fileManager: fileManager)
        try Self.validateContained(corruptStateFileURL, in: workspace.root, fileManager: fileManager)

        if fileManager.fileExists(atPath: stateFileURL.path) {
            do {
                state = try Self.decodeState(at: stateFileURL)
                try Self.validateUniqueIdentifiers(state)
            } catch {
                switch corruptionRecovery {
                case .fail:
                    throw QAFixtureStateError.corruptState(path: stateFileURL.path)
                case let .reset(recoverySeed):
                    if fileManager.fileExists(atPath: corruptStateFileURL.path) {
                        try fileManager.removeItem(at: corruptStateFileURL)
                    }
                    try fileManager.moveItem(at: stateFileURL, to: corruptStateFileURL)
                    state = PersistedState(seed: recoverySeed)
                    try Self.validateUniqueIdentifiers(state)
                    recoveredCorruptState = true
                }
            }
        } else {
            state = PersistedState(seed: seed)
            try Self.validateUniqueIdentifiers(state)
            try Self.persist(state, to: stateFileURL)
        }
        if recoveredCorruptState {
            var recovered = state
            try appendAudit(
                to: &recovered,
                subsystem: "fixture",
                operation: "recover-corrupt-state",
                targetID: nil,
                outcome: "succeeded"
            )
            try Self.persist(recovered, to: stateFileURL)
            state = recovered
        }
    }

    public func snapshot() -> QAFixtureOSSnapshot {
        lock.withLock { snapshot(of: state) }
    }

    public func reset(to seed: QAFixtureOSSeed) throws {
        try lock.withLock {
            var replacement = PersistedState(seed: seed)
            try Self.validateUniqueIdentifiers(replacement)
            try appendAudit(to: &replacement, subsystem: "fixture", operation: "reset", targetID: nil, outcome: "succeeded")
            try save(replacement)
        }
    }

    public func permission(_ permission: QAFixturePermission) -> QAFixturePermissionState {
        lock.withLock { state.permissions[permission] ?? .notDetermined }
    }

    public func setPermission(_ value: QAFixturePermissionState, for permission: QAFixturePermission) throws {
        try mutate(subsystem: "permissions", operation: "set", targetID: permission.rawValue) { state in
            state.permissions[permission] = value
        }
    }

    public func allReminders(includeCompleted: Bool = true) throws -> [SourceTask] {
        try lock.withLock {
            try requirePermission(.reminders, in: state)
            return state.reminders.filter { includeCompleted || !$0.isCompleted }
        }
    }

    public func syncReminders(_ reminders: [SourceTask]) throws {
        try mutate(subsystem: "reminders", operation: "sync", targetID: nil, permission: .reminders) { state in
            state.reminders = reminders
            try Self.validateUniqueIdentifiers(state)
        }
    }

    public func syncExternalCalendarCommitments(_ commitments: [CalendarCommitment]) throws {
        try mutate(subsystem: "calendar", operation: "sync-external", targetID: nil, permission: .calendar) { state in
            guard commitments.allSatisfy({ $0.ownershipToken == nil }) else {
                throw ActionSourceError.ownershipViolation
            }
            state.calendarCommitments.removeAll { $0.ownershipToken == nil }
            state.calendarCommitments.append(contentsOf: commitments)
            try Self.validateUniqueIdentifiers(state)
        }
    }

    @discardableResult
    public func deliverDueNotifications() throws -> [QAFixtureNotificationRecord] {
        var delivered: [QAFixtureNotificationRecord] = []
        try mutate(subsystem: "notifications", operation: "deliver-due", targetID: nil, permission: .notifications) { state in
            for index in state.notifications.indices where state.notifications[index].status == .scheduled {
                let record = state.notifications[index]
                guard record.desired.deliveryDate.map({ $0 <= clock.now() }) ?? true else { continue }
                let updated = QAFixtureNotificationRecord(
                    id: record.id,
                    desired: record.desired,
                    status: .delivered,
                    deliveredAt: clock.now()
                )
                state.notifications[index] = updated
                delivered.append(updated)
            }
        }
        return delivered
    }

    public func respondToNotification(identifier: String, actionIdentifier: String) throws -> QAFixtureNotificationRecord {
        var response: QAFixtureNotificationRecord?
        try mutate(subsystem: "notifications", operation: "respond", targetID: identifier, permission: .notifications) { state in
            guard let index = state.notifications.firstIndex(where: { $0.id == identifier }) else {
                throw ActionSourceError.missingEntity
            }
            let record = state.notifications[index]
            guard record.status == .delivered, !actionIdentifier.isEmpty else {
                throw ActionSourceError.invalidDesiredState
            }
            let updated = QAFixtureNotificationRecord(
                id: record.id,
                desired: record.desired,
                status: .responded,
                deliveredAt: record.deliveredAt,
                actionIdentifier: actionIdentifier,
                respondedAt: clock.now()
            )
            state.notifications[index] = updated
            response = updated
        }
        return response!
    }

    public func task(identifier: String) async throws -> SourceTask? {
        try lock.withLock {
            try requirePermission(.reminders, in: state)
            return state.reminders.first { $0.id == identifier }
        }
    }

    public func task(metadataMarker: String) async throws -> SourceTask? {
        try lock.withLock {
            try requirePermission(.reminders, in: state)
            return state.reminders.first { $0.metadataMarker == metadataMarker }
        }
    }

    public func create(title: String, dueDate: Date?, listIdentifier: String?, metadataMarker: String?) async throws -> SourceTask {
        var created: SourceTask?
        try mutate(subsystem: "reminders", operation: "create", targetID: nil, permission: .reminders) { state in
            let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedTitle.isEmpty, metadataMarker?.contains("\n") != true else {
                throw ActionSourceError.invalidDesiredState
            }
            let id = try nextID(.reminder, in: &state)
            let task = SourceTask(
                id: id,
                title: trimmedTitle,
                listIdentifier: listIdentifier ?? "qa-inbox",
                priority: 0,
                dueDate: dueDate,
                notes: nil,
                metadataMarker: metadataMarker,
                isCompleted: false
            )
            state.reminders.append(task)
            created = task
        }
        return created!
    }

    public func apply(_ mutation: TaskSourceMutation, to identifier: String) async throws -> SourceTask {
        var result: SourceTask?
        try mutate(subsystem: "reminders", operation: "mutate", targetID: identifier, permission: .reminders) { state in
            guard let index = state.reminders.firstIndex(where: { $0.id == identifier }) else {
                throw ActionSourceError.missingEntity
            }
            let old = state.reminders[index]
            let priority: Int
            let dueDate: Date?
            let marker: String?
            let completed: Bool
            switch mutation {
            case let .setPriority(value):
                guard [0, 1, 5, 9].contains(value) else {
                    throw ActionSourceError.invalidDesiredState
                }
                priority = value; dueDate = old.dueDate; marker = old.metadataMarker; completed = old.isCompleted
            case let .setDueDate(value):
                priority = old.priority; dueDate = value; marker = old.metadataMarker; completed = old.isCompleted
            case let .setMetadataMarker(value):
                guard value?.contains("\n") != true else {
                    throw ActionSourceError.invalidDesiredState
                }
                priority = old.priority; dueDate = old.dueDate; marker = value; completed = old.isCompleted
            case .complete:
                priority = old.priority; dueDate = old.dueDate; marker = old.metadataMarker; completed = true
            }
            let updated = SourceTask(
                id: old.id, title: old.title, listIdentifier: old.listIdentifier,
                priority: priority, dueDate: dueDate, notes: old.notes,
                metadataMarker: marker, isCompleted: completed
            )
            state.reminders[index] = updated
            result = updated
        }
        return result!
    }

    public func commitment(identifier: String) async throws -> CalendarCommitment? {
        try lock.withLock {
            try requirePermission(.calendar, in: state)
            return state.calendarCommitments.first { $0.id == identifier }
        }
    }

    public func ownedCommitment(ownershipToken: String) async throws -> CalendarCommitment? {
        try lock.withLock {
            try requirePermission(.calendar, in: state)
            return state.calendarCommitments.first { $0.ownershipToken == ownershipToken }
        }
    }

    public func confirmedMeeting(fingerprint: String) async throws -> CalendarCommitment? {
        try lock.withLock {
            try requirePermission(.calendar, in: state)
            return state.calendarCommitments.first { $0.meetingFingerprint == fingerprint }
        }
    }

    public func apply(_ mutation: CalendarSourceMutation) async throws -> CalendarCommitment? {
        var result: CalendarCommitment?
        try mutate(subsystem: "calendar", operation: "mutate", targetID: nil, permission: .calendar) { state in
            switch mutation {
            case let .createBlock(value):
                try Self.validateRange(start: value.start, end: value.end)
                guard !value.ownershipToken.isEmpty else { throw ActionSourceError.invalidDesiredState }
                if let existing = state.calendarCommitments.first(where: { $0.ownershipToken == value.ownershipToken }) {
                    result = existing
                    return
                }
                let block = CalendarCommitment(
                    id: try nextID(.calendarCommitment, in: &state), title: value.title,
                    start: value.start, end: value.end, calendarIdentifier: "qa-owned-work",
                    ownershipToken: value.ownershipToken
                )
                state.calendarCommitments.append(block)
                result = block
            case let .updateOwnedBlock(identifier, value):
                try Self.validateRange(start: value.start, end: value.end)
                guard let index = state.calendarCommitments.firstIndex(where: { $0.id == identifier }) else {
                    throw ActionSourceError.missingEntity
                }
                let old = state.calendarCommitments[index]
                guard old.ownershipToken != nil, old.ownershipToken == value.ownershipToken else {
                    throw ActionSourceError.ownershipViolation
                }
                let updated = CalendarCommitment(
                    id: old.id, title: value.title, start: value.start, end: value.end,
                    calendarIdentifier: old.calendarIdentifier, ownershipToken: old.ownershipToken
                )
                state.calendarCommitments[index] = updated
                result = updated
            case let .deleteOwnedBlock(identifier, token):
                guard let index = state.calendarCommitments.firstIndex(where: { $0.id == identifier }) else {
                    throw ActionSourceError.missingEntity
                }
                guard state.calendarCommitments[index].ownershipToken == token,
                      state.calendarCommitments[index].ownershipToken != nil else {
                    throw ActionSourceError.ownershipViolation
                }
                state.calendarCommitments.remove(at: index)
                result = nil
            case let .createConfirmedMeeting(value):
                try Self.validateRange(start: value.start, end: value.end)
                if let existing = state.calendarCommitments.first(where: { $0.meetingFingerprint == value.fingerprint }) {
                    result = existing
                    return
                }
                let meeting = CalendarCommitment(
                    id: try nextID(.calendarCommitment, in: &state), title: value.title,
                    start: value.start, end: value.end,
                    calendarIdentifier: value.calendarIdentifier ?? "qa-calendar",
                    meetingFingerprint: value.fingerprint, participants: value.participants
                )
                state.calendarCommitments.append(meeting)
                result = meeting
            }
        }
        return result
    }

    public func commitments(from start: Date, through end: Date, calendarIdentifiers: [String]) async throws -> [CalendarCommitment] {
        try lock.withLock {
            try requirePermission(.calendar, in: state)
            return state.calendarCommitments.filter {
                $0.start < end && $0.end > start &&
                    (calendarIdentifiers.isEmpty || calendarIdentifiers.contains($0.calendarIdentifier))
            }.sorted { $0.start < $1.start }
        }
    }

    public func pending(identifier: String) async throws -> Bool {
        try lock.withLock {
            try requirePermission(.notifications, in: state)
            return state.notifications.contains { $0.id == identifier && $0.status == .scheduled }
        }
    }

    public func schedule(_ desired: NotificationDesiredState) async throws -> String {
        var identifier = ""
        try mutate(subsystem: "notifications", operation: "schedule", targetID: nil, permission: .notifications) { state in
            guard !desired.promptID.isEmpty else { throw ActionSourceError.invalidDesiredState }
            identifier = desired.promptID
            let record = QAFixtureNotificationRecord(id: identifier, desired: desired)
            if let index = state.notifications.firstIndex(where: { $0.id == identifier }) {
                state.notifications[index] = record
            } else {
                state.notifications.append(record)
            }
        }
        return identifier
    }

    private func mutate<T>(
        subsystem: String,
        operation: String,
        targetID: String?,
        permission: QAFixturePermission? = nil,
        _ body: (inout PersistedState) throws -> T
    ) throws -> T {
        try lock.withLock {
            var updated = state
            do {
                if let permission { try requirePermission(permission, in: updated) }
                let result = try body(&updated)
                try appendAudit(to: &updated, subsystem: subsystem, operation: operation, targetID: targetID, outcome: "succeeded")
                try save(updated)
                return result
            } catch {
                var refused = state
                try appendAudit(to: &refused, subsystem: subsystem, operation: operation, targetID: targetID, outcome: "refused:\(String(describing: error))")
                try save(refused)
                throw error
            }
        }
    }

    private func save(_ replacement: PersistedState) throws {
        try Self.validateContained(stateFileURL, in: workspace.root, fileManager: fileManager)
        try Self.persist(replacement, to: stateFileURL)
        state = replacement
    }

    private func nextID(_ kind: QAFixtureEntityKind, in state: inout PersistedState) throws -> String {
        let index = state.counters[kind, default: 0]
        let value = stableID(kind, index)
        guard !value.isEmpty else { throw QAFixtureStateError.emptyStableIdentifier }
        let allIDs = state.reminders.map(\.id) + state.calendarCommitments.map(\.id) + state.notifications.map(\.id) + state.audit.map(\.id)
        guard !allIDs.contains(value) else { throw QAFixtureStateError.duplicateIdentifier(value) }
        state.counters[kind] = index + 1
        return value
    }

    private func appendAudit(to state: inout PersistedState, subsystem: String, operation: String, targetID: String?, outcome: String) throws {
        let id = try nextID(.audit, in: &state)
        state.audit.append(.init(
            id: id, timestamp: clock.now(), subsystem: subsystem,
            operation: operation, targetID: targetID, outcome: outcome
        ))
    }

    private func requirePermission(_ permission: QAFixturePermission, in state: PersistedState) throws {
        switch state.permissions[permission] ?? .notDetermined {
        case .granted: return
        case .denied, .restricted: throw ActionSourceError.accessDenied
        case .notDetermined: throw ActionSourceError.temporarilyUnavailable
        }
    }

    private func snapshot(of state: PersistedState) -> QAFixtureOSSnapshot {
        .init(
            permissions: state.permissions, reminders: state.reminders,
            calendarCommitments: state.calendarCommitments,
            notifications: state.notifications, audit: state.audit
        )
    }

    private static func validateRange(start: Date, end: Date) throws {
        guard start < end else { throw ActionSourceError.invalidDesiredState }
    }

    private static func validateUniqueIdentifiers(_ state: PersistedState) throws {
        let ids = state.reminders.map(\.id) + state.calendarCommitments.map(\.id) + state.notifications.map(\.id)
        guard ids.allSatisfy({ !$0.isEmpty }), Set(ids).count == ids.count else {
            throw QAFixtureStateError.duplicateIdentifier(ids.first ?? "unknown")
        }
    }

    private static func decodeState(at url: URL) throws -> PersistedState {
        let decoded = try JSONDecoder().decode(PersistedState.self, from: Data(contentsOf: url))
        guard decoded.schemaVersion == 1 else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return decoded
    }

    private static func persist(_ state: PersistedState, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(state).write(to: url, options: .atomic)
    }

    private static func validateContained(_ candidate: URL, in root: URL, fileManager: FileManager) throws {
        let canonicalRoot = root.resolvingSymlinksInPath().standardizedFileURL.path
        var ancestor = candidate.standardizedFileURL
        var suffix: [String] = []
        while !fileManager.fileExists(atPath: ancestor.path) {
            suffix.append(ancestor.lastPathComponent)
            ancestor.deleteLastPathComponent()
        }
        var canonical = ancestor.resolvingSymlinksInPath().standardizedFileURL
        for component in suffix.reversed() { canonical.appendPathComponent(component) }
        guard canonical.path.hasPrefix(canonicalRoot + "/") else {
            throw QAFixtureStateError.stateOutsideWorkspace(path: canonical.path)
        }
    }
}
