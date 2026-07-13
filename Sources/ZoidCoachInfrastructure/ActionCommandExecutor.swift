import Foundation
import ZoidCoachCore

public protocol ActionCommandQueue: Sendable {
    func executingCommands() async throws -> [ActionCommand]
    func claimNextReady() async throws -> ActionCommand?
    func markSucceeded(_ command: ActionCommand, platformIdentifier: String?) async throws
    func markFailed(
        _ command: ActionCommand,
        retryable: Bool,
        redactedError: String,
        retryAt: Date?
    ) async throws
}

extension ActionOutboxStore: ActionCommandQueue {}

public enum ActionExecutionResult: Equatable, Sendable {
    case idle
    case succeeded(commandID: String, platformIdentifier: String?)
    case reconciled(commandIDs: [String])
    case retryableFailure(commandID: String, reason: String)
    case terminalFailure(commandID: String, reason: String)
    case outboxFailure(reason: String)
}

public struct ActionCommandExecutor: Sendable {
    private let outbox: any ActionCommandQueue
    private let tasks: any TaskSource
    private let calendar: any CalendarSource
    private let notifications: any NotificationSource
    private let writeCircuitBreaker: DatabaseWriteCircuitBreaker
    private let now: @Sendable () -> Date

    public init(
        outbox: any ActionCommandQueue,
        tasks: any TaskSource,
        calendar: any CalendarSource,
        notifications: any NotificationSource = UnavailableNotificationSource(),
        writeCircuitBreaker: DatabaseWriteCircuitBreaker = DatabaseWriteCircuitBreaker(),
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.outbox = outbox
        self.tasks = tasks
        self.calendar = calendar
        self.notifications = notifications
        self.writeCircuitBreaker = writeCircuitBreaker
        self.now = now
    }

    public func executeNext() async -> ActionExecutionResult {
        do {
            try writeCircuitBreaker.throwIfTripped()
        } catch {
            return .outboxFailure(reason: "database_read_only")
        }
        do {
            let reconciled = try await reconcileInterruptedCommands()
            guard let command = try await outbox.claimNextReady() else {
                return reconciled.isEmpty ? .idle : .reconciled(commandIDs: reconciled)
            }
            return await execute(command)
        } catch {
            writeCircuitBreaker.trip(reason: "outbox_claim_or_reconcile_failed")
            return .outboxFailure(reason: "outbox_unavailable")
        }
    }

    private func execute(_ command: ActionCommand) async -> ActionExecutionResult {
        let platformIdentifier: String?
        do {
            platformIdentifier = try await perform(command)
        } catch {
            return await recordEffectFailure(command, error: error)
        }
        do {
            try await outbox.markSucceeded(command, platformIdentifier: platformIdentifier)
            return .succeeded(commandID: command.id, platformIdentifier: platformIdentifier)
        } catch {
            writeCircuitBreaker.trip(reason: "outbox_success_finalize_failed")
            return .outboxFailure(reason: "outbox_finalize_failed")
        }
    }

    private func recordEffectFailure(_ command: ActionCommand, error: Error) async -> ActionExecutionResult {
        let classification = classify(error)
        do {
            try await outbox.markFailed(
                command,
                retryable: classification.retryable,
                redactedError: classification.reason,
                retryAt: classification.retryable ? retryDate(for: command) : nil
            )
        } catch {
            writeCircuitBreaker.trip(reason: "outbox_failure_finalize_failed")
            return .outboxFailure(reason: "outbox_finalize_failed")
        }
        if classification.retryable {
            return .retryableFailure(commandID: command.id, reason: classification.reason)
        }
        return .terminalFailure(commandID: command.id, reason: classification.reason)
    }

    private func perform(_ command: ActionCommand) async throws -> String? {
        switch (command.type, command.desiredState) {
        case let (.createCalendarBlock, .calendarBlock(desired)):
            try validate(desired)
            if let existing = try await calendar.ownedCommitment(ownershipToken: desired.ownershipToken) {
                return existing.id
            }
            guard let created = try await calendar.apply(.createBlock(blockMutation(desired))) else {
                throw ActionSourceError.temporarilyUnavailable
            }
            return created.id

        case let (.updateCalendarBlock, .calendarBlock(desired)):
            try validate(desired)
            guard let existing = try await calendar.ownedCommitment(ownershipToken: desired.ownershipToken) else {
                if try await calendar.commitment(identifier: command.entityID) != nil {
                    throw ActionSourceError.ownershipViolation
                }
                throw ActionSourceError.missingEntity
            }
            guard let updated = try await calendar.apply(.updateOwnedBlock(identifier: existing.id, blockMutation(desired))) else {
                throw ActionSourceError.temporarilyUnavailable
            }
            return updated.id

        case let (.reconcileCalendarBlock, .calendarBlock(desired)):
            try validate(desired)
            if let existing = try await calendar.ownedCommitment(ownershipToken: desired.ownershipToken) {
                if existing.title == desired.title, existing.start == desired.start, existing.end == desired.end {
                    return existing.id
                }
                guard let updated = try await calendar.apply(.updateOwnedBlock(identifier: existing.id, blockMutation(desired))) else {
                    throw ActionSourceError.temporarilyUnavailable
                }
                return updated.id
            }
            guard let created = try await calendar.apply(.createBlock(blockMutation(desired))) else {
                throw ActionSourceError.temporarilyUnavailable
            }
            return created.id

        case let (.deleteCalendarBlock, .deleteOwnedCalendarBlock(ownershipToken)):
            guard !ownershipToken.isEmpty else { throw ActionSourceError.invalidDesiredState }
            guard let existing = try await calendar.ownedCommitment(ownershipToken: ownershipToken) else {
                if try await calendar.commitment(identifier: command.entityID) != nil {
                    throw ActionSourceError.ownershipViolation
                }
                return nil
            }
            _ = try await calendar.apply(.deleteOwnedBlock(identifier: existing.id, ownershipToken: ownershipToken))
            return existing.id

        case let (.setReminderPriority, .reminder(desired)):
            guard let priority = desired.priority, [0, 1, 5, 9].contains(priority) else {
                throw ActionSourceError.invalidDesiredState
            }
            _ = try await requiredTask(command.entityID)
            var updated = try await tasks.apply(.setPriority(priority), to: command.entityID)
            if let marker = desired.metadataMarker {
                updated = try await tasks.apply(.setMetadataMarker(marker), to: command.entityID)
            }
            return updated.id

        case let (.setReminderDueDate, .reminder(desired)):
            _ = try await requiredTask(command.entityID)
            guard desired.dueDate != nil || desired.shouldClearDueDate else {
                throw ActionSourceError.invalidDesiredState
            }
            var updated = try await tasks.apply(
                .setDueDate(desired.shouldClearDueDate ? nil : desired.dueDate),
                to: command.entityID
            )
            if let marker = desired.metadataMarker {
                updated = try await tasks.apply(.setMetadataMarker(marker), to: command.entityID)
            }
            return updated.id

        case let (.setReminderMetadata, .reminder(desired)):
            _ = try await requiredTask(command.entityID)
            return try await tasks.apply(.setMetadataMarker(desired.metadataMarker), to: command.entityID).id

        case (.completeReminder, .completeReminder):
            _ = try await requiredTask(command.entityID)
            return try await tasks.apply(.complete(at: now()), to: command.entityID).id

        case let (.createReminder, .createReminder(desired)):
            guard !desired.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw ActionSourceError.invalidDesiredState
            }
            if let marker = desired.metadataMarker,
               let existing = try await tasks.task(metadataMarker: marker) {
                return existing.id
            }
            return try await tasks.create(
                title: desired.title,
                dueDate: desired.dueDate,
                listIdentifier: desired.listIdentifier,
                metadataMarker: desired.metadataMarker
            ).id

        case let (.createConfirmedMeeting, .meeting(desired)):
            guard !desired.candidateFingerprint.isEmpty else { throw ActionSourceError.invalidDesiredState }
            if let existing = try await calendar.confirmedMeeting(fingerprint: desired.candidateFingerprint) {
                return existing.id
            }
            let meeting = ConfirmedMeetingMutation(
                title: desired.title,
                start: desired.start,
                end: desired.start.addingTimeInterval(TimeInterval(desired.durationMinutes * 60)),
                calendarIdentifier: desired.calendarIdentifier,
                fingerprint: desired.candidateFingerprint,
                participants: desired.participants,
                location: desired.location,
                callLink: desired.callLink,
                timezoneIdentifier: desired.timezoneIdentifier
            )
            guard let created = try await calendar.apply(.createConfirmedMeeting(meeting)) else {
                throw ActionSourceError.temporarilyUnavailable
            }
            return created.id

        case let (.scheduleNotification, .notification(desired)):
            guard !desired.promptID.isEmpty, !desired.title.isEmpty else {
                throw ActionSourceError.invalidDesiredState
            }
            return try await notifications.schedule(desired)

        default:
            throw ActionSourceError.invalidDesiredState
        }
    }

    private func requiredTask(_ identifier: String) async throws -> SourceTask {
        guard let task = try await tasks.task(identifier: identifier) else {
            throw ActionSourceError.missingEntity
        }
        return task
    }

    private func reconcileInterruptedCommands() async throws -> [String] {
        var recovered: [String] = []
        for command in try await outbox.executingCommands() {
            if let identifier = try await observedPlatformIdentifier(for: command) {
                try await outbox.markSucceeded(command, platformIdentifier: identifier)
                recovered.append(command.id)
            } else if command.type == .deleteCalendarBlock,
                      case let .deleteOwnedCalendarBlock(token) = command.desiredState,
                      try await calendar.ownedCommitment(ownershipToken: token) == nil {
                try await outbox.markSucceeded(command, platformIdentifier: nil)
                recovered.append(command.id)
            } else {
                try await outbox.markFailed(
                    command,
                    retryable: true,
                    redactedError: "interrupted_before_effect_was_observed",
                    retryAt: now()
                )
            }
        }
        return recovered
    }

    private func observedPlatformIdentifier(for command: ActionCommand) async throws -> String? {
        switch (command.type, command.desiredState) {
        case let (.createCalendarBlock, .calendarBlock(desired)),
             let (.updateCalendarBlock, .calendarBlock(desired)),
             let (.reconcileCalendarBlock, .calendarBlock(desired)):
            guard let block = try await calendar.ownedCommitment(ownershipToken: desired.ownershipToken),
                  block.title == desired.title,
                  block.start == desired.start,
                  block.end == desired.end
            else { return nil }
            return block.id
        case let (.setReminderPriority, .reminder(desired)):
            guard let priority = desired.priority,
                  let task = try await tasks.task(identifier: command.entityID),
                  task.priority == priority,
                  desired.metadataMarker == nil || task.metadataMarker == desired.metadataMarker
            else { return nil }
            return task.id
        case let (.createReminder, .createReminder(desired)):
            guard let marker = desired.metadataMarker else { return nil }
            return try await tasks.task(metadataMarker: marker)?.id
        case let (.setReminderDueDate, .reminder(desired)):
            guard let task = try await tasks.task(identifier: command.entityID),
                  task.dueDate == (desired.shouldClearDueDate ? nil : desired.dueDate),
                  desired.metadataMarker == nil || task.metadataMarker == desired.metadataMarker
            else { return nil }
            return task.id
        case let (.setReminderMetadata, .reminder(desired)):
            guard let task = try await tasks.task(identifier: command.entityID),
                  task.metadataMarker == desired.metadataMarker
            else { return nil }
            return task.id
        case (.completeReminder, .completeReminder):
            guard let task = try await tasks.task(identifier: command.entityID), task.isCompleted else { return nil }
            return task.id
        case let (.createConfirmedMeeting, .meeting(desired)):
            return try await calendar.confirmedMeeting(fingerprint: desired.candidateFingerprint)?.id
        case let (.scheduleNotification, .notification(desired)):
            return try await notifications.pending(identifier: desired.promptID) ? desired.promptID : nil
        default:
            return nil
        }
    }

    private func blockMutation(_ desired: CalendarBlockDesiredState) -> CalendarBlockMutation {
        CalendarBlockMutation(
            title: desired.title,
            start: desired.start,
            end: desired.end,
            ownershipToken: desired.ownershipToken,
            planItemID: desired.planItemID
        )
    }

    private func validate(_ desired: CalendarBlockDesiredState) throws {
        guard !desired.ownershipToken.isEmpty,
              !desired.planItemID.isEmpty,
              desired.start < desired.end
        else { throw ActionSourceError.invalidDesiredState }
    }

    private func classify(_ error: Error) -> (retryable: Bool, reason: String) {
        switch error as? ActionSourceError {
        case .temporarilyUnavailable:
            (true, "source_temporarily_unavailable")
        case .accessDenied:
            (false, "access_denied")
        case .missingEntity:
            (false, "missing_entity")
        case .ownershipViolation:
            (false, "ownership_violation")
        case .invalidDesiredState:
            (false, "invalid_desired_state")
        case .unsupported:
            (false, "unsupported_action")
        case nil:
            (true, "source_error")
        }
    }

    private func retryDate(for command: ActionCommand) -> Date {
        let exponent = min(max(command.attemptCount - 1, 0), 6)
        return now().addingTimeInterval(30 * pow(2, Double(exponent)))
    }
}
