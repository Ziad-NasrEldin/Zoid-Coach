import Foundation
import ZoidCoachCore

public enum QAFixtureStateError: LocalizedError, Equatable, Sendable {
    case qaWorkspaceRequired
    case stateOutsideWorkspace(path: String)
    case corruptState(path: String)
    case duplicateIdentifier(String)
    case emptyStableIdentifier
    case invalidPersistedState(String)
    case unsafeFilesystemEntry(String)
    case filesystemOperation(String, Int32)
    case controlRequestConflict(String)
    case injectedNotificationSchedulingFailure(String)

    public var errorDescription: String? {
        switch self {
        case .qaWorkspaceRequired:
            "The deterministic OS fixture requires a validated QA workspace."
        case let .stateOutsideWorkspace(path):
            "The fixture state path is outside the validated QA workspace: \(path)"
        case let .corruptState(path):
            "The fixture state is corrupt or unreadable at: \(path)"
        case let .duplicateIdentifier(identifier):
            "The fixture contains a duplicate identifier: \(identifier)"
        case .emptyStableIdentifier:
            "The fixture stable identifier provider returned an empty identifier."
        case let .invalidPersistedState(reason):
            "The persisted fixture state is invalid: \(reason)"
        case let .unsafeFilesystemEntry(entry):
            "The fixture refused an unsafe filesystem entry: \(entry)"
        case let .filesystemOperation(operation, code):
            "The fixture filesystem operation '\(operation)' failed with POSIX code \(code)."
        case let .controlRequestConflict(requestID):
            "The fixture control requestID '\(requestID)' was reused with different content."
        case let .injectedNotificationSchedulingFailure(reason):
            "The QA fixture deliberately refused notification scheduling: \(reason)"
        }
    }
}

public enum QAFixtureCorruptionRecovery: Sendable {
    case fail
    case reset(QAFixtureOSSeed)
}

public enum QAFixtureStorageCheckpoint: Sendable {
    case beforeStateCommit
    case recoveryPrepared
    case corruptStateQuarantined
    case replacementStatePersisted
}

public final class DeterministicOSFixtureAdapters: TaskSource, CalendarSource,
    CalendarAvailabilitySource, NotificationSource, @unchecked Sendable {
    public typealias StableIDProvider = @Sendable (QAFixtureEntityKind, Int) -> String

    private struct GeneratedIdentifier: Codable {
        enum Provenance: String, Codable { case stableProvider, callerSupplied }
        let kind: QAFixtureEntityKind
        let index: Int
        let id: String
        let provenance: Provenance
    }

    private struct ControlReceipt: Codable {
        let request: QAFixtureOSControlRequest
        let snapshot: QAFixtureOSSnapshot
    }

    private struct PersistedState: Codable {
        var schemaVersion = 1
        var permissions: [QAFixturePermission: QAFixturePermissionState]
        var reminderLists: [QAFixtureReminderList]
        var reminders: [SourceTask]
        var calendarCommitments: [CalendarCommitment]
        var notifications: [QAFixtureNotificationRecord]
        var notificationSchedulingFailure: String?
        var audit: [QAFixtureOperationAuditEntry]
        var counters: [QAFixtureEntityKind: Int]
        var generatedIdentifiers: [GeneratedIdentifier]
        var controlReceipts: [ControlReceipt]

        private enum CodingKeys: String, CodingKey {
            case schemaVersion, permissions, reminderLists, reminders, calendarCommitments, notifications
            case notificationSchedulingFailure
            case audit, counters, generatedIdentifiers, controlReceipts
        }

        init(seed: QAFixtureOSSeed) {
            permissions = seed.permissions
            reminderLists = seed.reminderLists
            reminders = seed.reminders
            calendarCommitments = seed.calendarCommitments
            notifications = seed.notifications
            notificationSchedulingFailure = seed.notificationSchedulingFailure
            audit = []
            counters = [:]
            generatedIdentifiers = []
            controlReceipts = []
        }

        init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            schemaVersion = try values.decode(Int.self, forKey: .schemaVersion)
            permissions = try values.decode(
                [QAFixturePermission: QAFixturePermissionState].self,
                forKey: .permissions
            )
            reminderLists = try values.decodeIfPresent(
                [QAFixtureReminderList].self,
                forKey: .reminderLists
            ) ?? []
            reminders = try values.decode([SourceTask].self, forKey: .reminders)
            calendarCommitments = try values.decode(
                [CalendarCommitment].self,
                forKey: .calendarCommitments
            )
            notifications = try values.decode(
                [QAFixtureNotificationRecord].self,
                forKey: .notifications
            )
            notificationSchedulingFailure = try values.decodeIfPresent(
                String.self,
                forKey: .notificationSchedulingFailure
            )
            audit = try values.decode([QAFixtureOperationAuditEntry].self, forKey: .audit)
            counters = try values.decode([QAFixtureEntityKind: Int].self, forKey: .counters)
            generatedIdentifiers = try values.decode(
                [GeneratedIdentifier].self,
                forKey: .generatedIdentifiers
            )
            controlReceipts = try values.decodeIfPresent(
                [ControlReceipt].self,
                forKey: .controlReceipts
            ) ?? []
        }
    }

    private struct RecoveryTransaction: Codable {
        enum Phase: String, Codable { case prepared, quarantined, replacementWritten }
        var phase: Phase
        let replacement: PersistedState
    }

    private let clock: ZoidClock
    private let stableID: StableIDProvider
    private let storage: DescriptorRelativeStateDirectory<QAFixtureStateError>
    private let storageCheckpoint: @Sendable (QAFixtureStorageCheckpoint) throws -> Void
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
        fileManager _: FileManager = .default,
        storageCheckpoint: @escaping @Sendable (QAFixtureStorageCheckpoint) throws -> Void = { _ in }
    ) throws {
        guard case let .qa(runRoot) = workspace.environment.mode,
              runRoot.standardizedFileURL == workspace.root.standardizedFileURL else {
            throw QAFixtureStateError.qaWorkspaceRequired
        }
        self.clock = clock
        self.stableID = stableID
        self.storageCheckpoint = storageCheckpoint
        let directory = workspace.root.appendingPathComponent("OS Fixtures", isDirectory: true)
        stateFileURL = directory.appendingPathComponent("state.json")
        corruptStateFileURL = directory.appendingPathComponent("state.corrupt.json")
        storage = try DescriptorRelativeStateDirectory(
            rootURL: workspace.root,
            directoryName: "OS Fixtures",
            createRootIfMissing: true,
            unsafeEntryError: QAFixtureStateError.unsafeFilesystemEntry,
            filesystemError: QAFixtureStateError.filesystemOperation
        )
        state = PersistedState(seed: seed)
        try storage.acquire(exclusive: true)
        defer { storage.release() }

        if try storage.exists("recovery.json") {
            let transaction = try Self.decode(
                RecoveryTransaction.self,
                data: storage.read("recovery.json"),
                path: stateFileURL.path
            )
            state = try resumeRecovery(transaction)
        } else if try storage.exists("state.json") {
            do {
                state = try Self.decode(
                    PersistedState.self,
                    data: storage.read("state.json"),
                    path: stateFileURL.path
                )
                try validatePersistedState(state)
            } catch {
                switch corruptionRecovery {
                case .fail:
                    throw QAFixtureStateError.corruptState(path: stateFileURL.path)
                case let .reset(recoverySeed):
                    var replacement = PersistedState(seed: recoverySeed)
                    let timestamp = clock.now()
                    try appendAudit(
                        to: &replacement,
                        subsystem: "fixture",
                        operation: "recover-corrupt-state",
                        targetID: nil,
                        outcome: "succeeded",
                        timestamp: timestamp
                    )
                    try validatePersistedState(replacement)
                    let transaction = RecoveryTransaction(phase: .prepared, replacement: replacement)
                    try storage.writeAtomic(try Self.encode(transaction), name: "recovery.json")
                    try storageCheckpoint(.recoveryPrepared)
                    state = try resumeRecovery(transaction)
                }
            }
        } else {
            state = PersistedState(seed: seed)
            try validatePersistedState(state)
            try persist(state)
        }
    }

    public func snapshot() throws -> QAFixtureOSSnapshot {
        try withLatestState { snapshot(of: $0) }
    }

    public func reset(to seed: QAFixtureOSSeed) throws {
        try lock.withLock {
            try storage.withLock(exclusive: true) {
                state = try loadPersistedState()
                var replacement = PersistedState(seed: seed)
                let timestamp = clock.now()
                try appendAudit(to: &replacement, subsystem: "fixture", operation: "reset", targetID: nil, outcome: "succeeded", timestamp: timestamp)
                try save(replacement, allowCounterReset: true)
            }
        }
    }

    func applyControl(
        _ request: QAFixtureOSControlRequest,
        notificationIdentity: RuntimeNotificationIdentity
    ) throws -> QAFixtureOSSnapshot {
        try lock.withLock {
            try storage.withLock(exclusive: true) {
                state = try loadPersistedState()
                if let receipt = state.controlReceipts.first(where: {
                    $0.request.requestID == request.requestID
                }) {
                    guard receipt.request == request else {
                        throw QAFixtureStateError.controlRequestConflict(request.requestID)
                    }
                    return receipt.snapshot
                }

                let timestamp = clock.now()
                var replacement = state
                var allowsCounterReset = false
                switch request.operation {
                case .seed:
                    guard let seed = request.seed else {
                        throw QAFixtureOSCompositionError.malformedControl
                    }
                    replacement = PersistedState(seed: seed)
                    replacement.controlReceipts = state.controlReceipts
                    allowsCounterReset = true
                    try appendAudit(
                        to: &replacement,
                        subsystem: "fixture",
                        operation: "seed",
                        targetID: request.requestID,
                        outcome: "succeeded",
                        timestamp: timestamp
                    )
                case .reset:
                    replacement = PersistedState(seed: request.seed ?? .init())
                    replacement.controlReceipts = state.controlReceipts
                    allowsCounterReset = true
                    try appendAudit(
                        to: &replacement,
                        subsystem: "fixture",
                        operation: "reset",
                        targetID: request.requestID,
                        outcome: "succeeded",
                        timestamp: timestamp
                    )
                case .snapshot:
                    try appendAudit(
                        to: &replacement,
                        subsystem: "fixture-control",
                        operation: "snapshot",
                        targetID: request.requestID,
                        outcome: "succeeded",
                        timestamp: timestamp
                    )
                case .notificationAction:
                    try requirePermission(.notifications, in: replacement)
                    for index in replacement.notifications.indices
                        where replacement.notifications[index].status == .scheduled {
                        let record = replacement.notifications[index]
                        guard record.desired.deliveryDate.map({ $0 <= timestamp }) ?? true else {
                            continue
                        }
                        replacement.notifications[index] = QAFixtureNotificationRecord(
                            id: record.id,
                            desired: record.desired,
                            status: .delivered,
                            deliveredAt: timestamp
                        )
                    }
                    guard let notificationID = request.notificationID,
                          let actionIdentifier = request.actionIdentifier,
                          let index = replacement.notifications.firstIndex(where: {
                            $0.id == notificationID
                          }) else {
                        throw ActionSourceError.missingEntity
                    }
                    let record = replacement.notifications[index]
                    guard PromptNotificationCoordinator.fixtureActionKind(
                        identifier: actionIdentifier,
                        category: record.desired.category,
                        notificationIdentity: notificationIdentity
                    ) != nil else {
                        throw QAFixtureOSCompositionError.invalidNotificationAction(actionIdentifier)
                    }
                    guard record.status == .delivered else {
                        throw ActionSourceError.invalidDesiredState
                    }
                    replacement.notifications[index] = QAFixtureNotificationRecord(
                        id: record.id,
                        desired: record.desired,
                        status: .responded,
                        deliveredAt: record.deliveredAt,
                        actionIdentifier: actionIdentifier,
                        respondedAt: timestamp
                    )
                    try appendAudit(
                        to: &replacement,
                        subsystem: "notifications",
                        operation: "respond",
                        targetID: notificationID,
                        outcome: "succeeded",
                        timestamp: timestamp
                    )
                }

                let result = snapshot(of: replacement)
                replacement.controlReceipts.append(.init(request: request, snapshot: result))
                try save(replacement, allowCounterReset: allowsCounterReset)
                return result
            }
        }
    }

    public func permission(_ permission: QAFixturePermission) throws -> QAFixturePermissionState {
        try withLatestState { $0.permissions[permission] ?? .notDetermined }
    }

    public func setPermission(_ value: QAFixturePermissionState, for permission: QAFixturePermission) throws {
        try mutate(subsystem: "permissions", operation: "set", targetID: permission.rawValue) { state in
            state.permissions[permission] = value
        }
    }

    public func allReminders(includeCompleted: Bool = true) throws -> [SourceTask] {
        try withLatestState { latest in
            try requirePermission(.reminders, in: latest)
            return latest.reminders.filter { includeCompleted || !$0.isCompleted }
        }
    }

    public func syncReminders(_ reminders: [SourceTask]) throws {
        try mutate(subsystem: "reminders", operation: "sync", targetID: nil, permission: .reminders) { state in
            state.reminders = reminders
            try validatePersistedState(state)
        }
    }

    public func syncExternalCalendarCommitments(_ commitments: [CalendarCommitment]) throws {
        try mutate(subsystem: "calendar", operation: "sync-external", targetID: nil, permission: .calendar) { state in
            guard commitments.allSatisfy({ $0.ownershipToken == nil }) else {
                throw ActionSourceError.ownershipViolation
            }
            state.calendarCommitments.removeAll { $0.ownershipToken == nil }
            state.calendarCommitments.append(contentsOf: commitments)
            try validatePersistedState(state)
        }
    }

    @discardableResult
    public func deliverDueNotifications() throws -> [QAFixtureNotificationRecord] {
        var delivered: [QAFixtureNotificationRecord] = []
        let timestamp = clock.now()
        try mutate(subsystem: "notifications", operation: "deliver-due", targetID: nil, permission: .notifications, timestamp: timestamp) { state in
            for index in state.notifications.indices where state.notifications[index].status == .scheduled {
                let record = state.notifications[index]
                guard record.desired.deliveryDate.map({ $0 <= timestamp }) ?? true else { continue }
                let updated = QAFixtureNotificationRecord(
                    id: record.id,
                    desired: record.desired,
                    status: .delivered,
                    deliveredAt: timestamp
                )
                state.notifications[index] = updated
                delivered.append(updated)
            }
        }
        return delivered
    }

    public func respondToNotification(identifier: String, actionIdentifier: String) throws -> QAFixtureNotificationRecord {
        var response: QAFixtureNotificationRecord?
        let timestamp = clock.now()
        try mutate(subsystem: "notifications", operation: "respond", targetID: identifier, permission: .notifications, timestamp: timestamp) { state in
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
                respondedAt: timestamp
            )
            state.notifications[index] = updated
            response = updated
        }
        return response!
    }

    public func task(identifier: String) async throws -> SourceTask? {
        try withLatestState { latest in
            try requirePermission(.reminders, in: latest)
            return latest.reminders.first { $0.id == identifier }
        }
    }

    public func task(metadataMarker: String) async throws -> SourceTask? {
        try withLatestState { latest in
            try requirePermission(.reminders, in: latest)
            return latest.reminders.first { $0.metadataMarker == metadataMarker }
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
                metadataMarker: metadataMarker?.isEmpty == false ? metadataMarker : nil,
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
                priority = old.priority; dueDate = old.dueDate; marker = value?.isEmpty == false ? value : nil; completed = old.isCompleted
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
        try withLatestState { latest in
            try requirePermission(.calendar, in: latest)
            return latest.calendarCommitments.first { $0.id == identifier }
        }
    }

    public func ownedCommitment(ownershipToken: String) async throws -> CalendarCommitment? {
        try withLatestState { latest in
            try requirePermission(.calendar, in: latest)
            return latest.calendarCommitments.first { $0.ownershipToken == ownershipToken }
        }
    }

    public func confirmedMeeting(fingerprint: String) async throws -> CalendarCommitment? {
        try withLatestState { latest in
            try requirePermission(.calendar, in: latest)
            return latest.calendarCommitments.first { $0.meetingFingerprint == fingerprint }
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
                guard let index = state.calendarCommitments.firstIndex(where: { $0.id == identifier }) else { return }
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
        try withLatestState { latest in
            try requirePermission(.calendar, in: latest)
            return latest.calendarCommitments.filter {
                $0.start < end && $0.end > start &&
                    (calendarIdentifiers.isEmpty || calendarIdentifiers.contains($0.calendarIdentifier))
            }.sorted {
                if $0.start != $1.start { return $0.start < $1.start }
                if $0.end != $1.end { return $0.end < $1.end }
                return $0.id < $1.id
            }
        }
    }

    public func pending(identifier: String) async throws -> Bool {
        try withLatestState { latest in
            try requirePermission(.notifications, in: latest)
            return latest.notifications.contains { $0.id == identifier && $0.status == .scheduled }
        }
    }

    public func schedule(_ desired: NotificationDesiredState) async throws -> String {
        var identifier = ""
        try mutate(subsystem: "notifications", operation: "schedule", targetID: nil, permission: .notifications) { state in
            if let reason = state.notificationSchedulingFailure {
                throw QAFixtureStateError.injectedNotificationSchedulingFailure(reason)
            }
            guard !desired.promptID.isEmpty,
                  !desired.category.isEmpty,
                  !desired.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !desired.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw ActionSourceError.invalidDesiredState
            }
            identifier = desired.promptID
            let record = QAFixtureNotificationRecord(id: identifier, desired: desired)
            if let index = state.notifications.firstIndex(where: { $0.id == identifier }) {
                state.notifications[index] = record
            } else {
                try recordCallerSuppliedID(identifier, kind: .notification, in: &state)
                state.notifications.append(record)
            }
        }
        return identifier
    }

    public func cancelNotifications(withPrefix prefix: String, keeping identifier: String? = nil) throws {
        try mutate(
            subsystem: "notifications",
            operation: "cancel-prefix",
            targetID: prefix
        ) { state in
            state.notifications.removeAll {
                $0.id.hasPrefix(prefix) && $0.id != identifier
            }
        }
    }

    private func mutate<T>(
        subsystem: String,
        operation: String,
        targetID: String?,
        permission: QAFixturePermission? = nil,
        timestamp: Date? = nil,
        _ body: (inout PersistedState) throws -> T
    ) throws -> T {
        try lock.withLock {
            try storage.withLock(exclusive: true) {
                state = try loadPersistedState()
                let operationTimestamp = timestamp ?? clock.now()
                var updated = state
                do {
                    if let permission { try requirePermission(permission, in: updated) }
                    let result = try body(&updated)
                    try appendAudit(to: &updated, subsystem: subsystem, operation: operation, targetID: targetID, outcome: "succeeded", timestamp: operationTimestamp)
                    try save(updated)
                    return result
                } catch {
                    var refused = state
                    try appendAudit(to: &refused, subsystem: subsystem, operation: operation, targetID: targetID, outcome: "refused:\(String(describing: error))", timestamp: operationTimestamp)
                    try save(refused)
                    throw error
                }
            }
        }
    }

    private func withLatestState<T>(_ body: (PersistedState) throws -> T) throws -> T {
        try lock.withLock {
            try storage.withLock(exclusive: true) {
                let latest = try loadPersistedState()
                state = latest
                return try body(latest)
            }
        }
    }

    private func loadPersistedState() throws -> PersistedState {
        if try storage.exists("recovery.json") {
            let transaction = try Self.decode(
                RecoveryTransaction.self,
                data: storage.read("recovery.json"),
                path: stateFileURL.path
            )
            return try resumeRecovery(transaction)
        }
        guard try storage.exists("state.json") else {
            throw QAFixtureStateError.corruptState(path: stateFileURL.path)
        }
        let latest = try Self.decode(
            PersistedState.self,
            data: storage.read("state.json"),
            path: stateFileURL.path
        )
        try validatePersistedState(latest)
        return latest
    }

    private func save(_ replacement: PersistedState, allowCounterReset: Bool = false) throws {
        try validatePersistedState(replacement)
        if !allowCounterReset {
            for kind in [QAFixtureEntityKind.reminder, .calendarCommitment, .notification, .audit] {
                guard replacement.counters[kind, default: 0] >= state.counters[kind, default: 0] else {
                    throw QAFixtureStateError.invalidPersistedState("counter regressed: \(kind.rawValue)")
                }
            }
        }
        try persist(replacement)
        state = replacement
    }

    private func nextID(_ kind: QAFixtureEntityKind, in state: inout PersistedState) throws -> String {
        let index = state.counters[kind, default: 0]
        guard index < Int.max else {
            throw QAFixtureStateError.invalidPersistedState("identifier counter exhausted")
        }
        let value = stableID(kind, index)
        guard !value.isEmpty else { throw QAFixtureStateError.emptyStableIdentifier }
        let allIDs = state.reminders.map(\.id) + state.calendarCommitments.map(\.id) + state.notifications.map(\.id) + state.audit.map(\.id) + state.generatedIdentifiers.map(\.id)
        guard !allIDs.contains(value) else { throw QAFixtureStateError.duplicateIdentifier(value) }
        state.counters[kind] = index + 1
        state.generatedIdentifiers.append(.init(
            kind: kind, index: index, id: value, provenance: .stableProvider
        ))
        return value
    }

    private func recordCallerSuppliedID(_ id: String, kind: QAFixtureEntityKind, in state: inout PersistedState) throws {
        let index = state.counters[kind, default: 0]
        guard index < Int.max,
              !state.generatedIdentifiers.contains(where: { $0.id == id }) else {
            throw QAFixtureStateError.invalidPersistedState("identifier allocation reused")
        }
        state.counters[kind] = index + 1
        state.generatedIdentifiers.append(.init(
            kind: kind, index: index, id: id, provenance: .callerSupplied
        ))
    }

    private func appendAudit(to state: inout PersistedState, subsystem: String, operation: String, targetID: String?, outcome: String, timestamp: Date) throws {
        let id = try nextID(.audit, in: &state)
        state.audit.append(.init(
            id: id, timestamp: timestamp, subsystem: subsystem,
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
            permissions: state.permissions,
            reminderLists: Self.canonicalReminderLists(state),
            reminders: state.reminders,
            calendarCommitments: state.calendarCommitments,
            notifications: state.notifications, audit: state.audit
        )
    }

    private static func canonicalReminderLists(
        _ state: PersistedState
    ) -> [QAFixtureReminderList] {
        var byID: [String: QAFixtureReminderList] = [:]
        for list in state.reminderLists where byID[list.id] == nil {
            byID[list.id] = list
        }
        for listID in Set(state.reminders.map(\.listIdentifier)) where byID[listID] == nil {
            byID[listID] = QAFixtureReminderList(id: listID, name: listID)
        }
        return byID.values.sorted {
            if $0.name == $1.name { return $0.id < $1.id }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    private static func validateRange(start: Date, end: Date) throws {
        guard start < end else { throw ActionSourceError.invalidDesiredState }
    }

    private func validatePersistedState(_ state: PersistedState) throws {
        guard state.schemaVersion == 1 else {
            throw QAFixtureStateError.invalidPersistedState("unsupported schema")
        }
        if let failure = state.notificationSchedulingFailure {
            guard !failure.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  failure.count <= 120,
                  !failure.contains("\n"),
                  !failure.contains("\r") else {
                throw QAFixtureStateError.invalidPersistedState("invalid notification failure injection")
            }
        }
        let controlRequestIDs = state.controlReceipts.map(\.request.requestID)
        guard controlRequestIDs.allSatisfy({
            !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }), Self.areUnique(controlRequestIDs) else {
            throw QAFixtureStateError.invalidPersistedState("invalid control receipt ledger")
        }
        let ids = state.reminders.map(\.id)
            + state.calendarCommitments.map(\.id)
            + state.notifications.map(\.id)
            + state.audit.map(\.id)
        guard ids.allSatisfy({ !$0.isEmpty }) else {
            throw QAFixtureStateError.invalidPersistedState("empty identifier")
        }
        guard Set(ids).count == ids.count else {
            throw QAFixtureStateError.duplicateIdentifier(ids.first(where: { id in ids.filter { $0 == id }.count > 1 }) ?? "unknown")
        }
        let reminderListIDs = state.reminderLists.map(\.id)
        guard reminderListIDs.allSatisfy({
            !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }),
        state.reminderLists.allSatisfy({
            !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }),
        Self.areUnique(reminderListIDs) else {
            throw QAFixtureStateError.invalidPersistedState("invalid reminder lists")
        }
        guard state.reminders.allSatisfy({
                  !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                      && !$0.listIdentifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                      && [0, 1, 5, 9].contains($0.priority)
                      && $0.metadataMarker?.isEmpty != true
              }),
              state.calendarCommitments.allSatisfy({ !$0.calendarIdentifier.isEmpty && $0.start < $0.end }),
              state.calendarCommitments.allSatisfy({ $0.ownershipToken?.isEmpty != true && $0.meetingFingerprint?.isEmpty != true }),
              state.notifications.allSatisfy({
                  !$0.desired.promptID.isEmpty
                      && $0.id == $0.desired.promptID
                      && !$0.desired.category.isEmpty
                      && !$0.desired.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                      && !$0.desired.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                      && $0.actionIdentifier?.isEmpty != true
              }),
              state.audit.allSatisfy({ !$0.subsystem.isEmpty && !$0.operation.isEmpty && !$0.outcome.isEmpty && $0.targetID?.isEmpty != true }),
              Self.areUnique(state.reminders.compactMap(\.metadataMarker)),
              Self.areUnique(state.calendarCommitments.compactMap(\.ownershipToken)),
              Self.areUnique(state.calendarCommitments.compactMap(\.meetingFingerprint)) else {
            throw QAFixtureStateError.invalidPersistedState("invalid persisted identifier")
        }
        guard state.counters.values.allSatisfy({ $0 >= 0 && $0 < Int.max }),
              state.generatedIdentifiers.allSatisfy({ !$0.id.isEmpty && $0.index >= 0 }),
              Self.areUnique(state.generatedIdentifiers.map(\.id)) else {
            throw QAFixtureStateError.invalidPersistedState("invalid identifier counter")
        }
        for kind in [QAFixtureEntityKind.reminder, .calendarCommitment, .notification, .audit] {
            let allocations = state.generatedIdentifiers
                .filter { $0.kind == kind }
                .sorted { $0.index < $1.index }
            guard allocations.map(\.index) == Array(0 ..< allocations.count),
                  state.counters[kind, default: 0] == allocations.count else {
                throw QAFixtureStateError.invalidPersistedState("counter does not match allocations: \(kind.rawValue)")
            }
        }
        guard state.generatedIdentifiers.allSatisfy({ allocation in
            switch (allocation.kind, allocation.provenance) {
            case (.notification, .callerSupplied):
                true
            case (.reminder, .stableProvider),
                 (.calendarCommitment, .stableProvider),
                 (.audit, .stableProvider):
                stableID(allocation.kind, allocation.index) == allocation.id
            default:
                false
            }
        }) else {
            throw QAFixtureStateError.invalidPersistedState("generated identifier provenance mismatch")
        }
        let auditIDs = Set(state.audit.map(\.id))
        let allocationKinds = Dictionary(
            uniqueKeysWithValues: state.generatedIdentifiers.map { ($0.id, $0.kind) }
        )
        guard state.reminders.allSatisfy({ allocationKinds[$0.id].map { $0 == .reminder } ?? true }),
              state.calendarCommitments.allSatisfy({ allocationKinds[$0.id].map { $0 == .calendarCommitment } ?? true }),
              state.notifications.allSatisfy({ allocationKinds[$0.id].map { $0 == .notification } ?? true }),
              state.audit.allSatisfy({ allocationKinds[$0.id] == .audit }) else {
            throw QAFixtureStateError.invalidPersistedState("allocated identifier changed domain")
        }
        guard state.generatedIdentifiers.allSatisfy({ allocation in
            switch allocation.kind {
            case .reminder: true
            // Caller-supplied notification IDs remain allocated as tombstones after cancellation.
            // This preserves monotonic counters and prevents an old request identity being reused.
            case .notification: true
            case .audit: auditIDs.contains(allocation.id)
            case .calendarCommitment: true
            }
        }) else {
            throw QAFixtureStateError.invalidPersistedState("allocation has no persisted entity")
        }
        for notification in state.notifications {
            switch notification.status {
            case .scheduled:
                guard notification.deliveredAt == nil,
                      notification.actionIdentifier == nil,
                      notification.respondedAt == nil else {
                    throw QAFixtureStateError.invalidPersistedState("invalid scheduled notification")
                }
            case .delivered:
                guard notification.deliveredAt != nil,
                      notification.actionIdentifier == nil,
                      notification.respondedAt == nil,
                      notification.desired.deliveryDate.map({ $0 <= notification.deliveredAt! }) ?? true else {
                    throw QAFixtureStateError.invalidPersistedState("invalid delivered notification")
                }
            case .responded:
                guard notification.deliveredAt != nil,
                      notification.actionIdentifier != nil,
                      notification.respondedAt != nil,
                      notification.respondedAt! >= notification.deliveredAt!,
                      notification.desired.deliveryDate.map({ $0 <= notification.deliveredAt! }) ?? true else {
                    throw QAFixtureStateError.invalidPersistedState("invalid notification response")
                }
            }
        }
    }

    private static func areUnique(_ values: [String]) -> Bool {
        Set(values).count == values.count
    }

    private static func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(value)
    }

    private static func decode<T: Decodable>(_ type: T.Type, data: Data, path: String) throws -> T {
        do { return try JSONDecoder().decode(type, from: data) }
        catch { throw QAFixtureStateError.corruptState(path: path) }
    }

    private func persist(_ replacement: PersistedState) throws {
        try storage.writeAtomic(try Self.encode(replacement), name: "state.json") {
            try storageCheckpoint(.beforeStateCommit)
        }
    }

    private func resumeRecovery(_ initial: RecoveryTransaction) throws -> PersistedState {
        var transaction = initial
        try validatePersistedState(transaction.replacement)
        if transaction.phase == .prepared {
            if try storage.exists("state.json") {
                try storage.rename("state.json", to: "state.corrupt.json")
            }
            transaction.phase = .quarantined
            try storage.writeAtomic(try Self.encode(transaction), name: "recovery.json")
            try storageCheckpoint(.corruptStateQuarantined)
        }
        if transaction.phase == .quarantined {
            try persist(transaction.replacement)
            transaction.phase = .replacementWritten
            try storage.writeAtomic(try Self.encode(transaction), name: "recovery.json")
            try storageCheckpoint(.replacementStatePersisted)
        }
        try storage.removeIfPresent("recovery.json")
        return transaction.replacement
    }
}
